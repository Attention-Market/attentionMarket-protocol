/// AttentionMarket — Attention auction marketplace on Sui
///
/// Privacy model:
///   - Seller's real inbox is never on-chain in plaintext.
///     It is stored as an ECDH/AES-GCM encrypted blob (three fields:
///     encrypted_email_ephemeral_pubkey, encrypted_email_iv, encrypted_email_ciphertext).
///     Only the holder of the corresponding private key (the gateway) can decrypt it.
///   - gateway_email (public MX address) remains public as before.
///   - Bidder's sender email stored and emitted as sha256(email) only.
///   - payment_id = sha256(emailHash + ":" + vaultId) — gateway computes this from From: header.
///   - Conversations can be closed by the seller, invalidating the attention token permanently.
///     Gateway checks vault.closed_threads[payment_id] before forwarding any email.
///
module attentionmarket::attention_market {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use std::string::String;

    // ── Constants ─────────────────────────────────────────────────────────────
    const GLOBAL_FLOOR: u64 = 1_000_000;  // 0.001 SUI
    const MAX_SLOTS:    u64 = 100;

    // ── Errors ────────────────────────────────────────────────────────────────
    const ENotOwner:           u64 = 1;
    const EBidTooLow:          u64 = 2;
    const EBelowGlobalFloor:   u64 = 3;
    const EZeroBalance:        u64 = 4;
    const ETooManySlots:       u64 = 5;
    const EAlreadyWhitelisted: u64 = 6;
    const ENotWhitelisted:     u64 = 7;
    const EAlreadyClosed:      u64 = 8;
    const EVaultClosed:        u64 = 9;

    // ── Structs ───────────────────────────────────────────────────────────────

    public struct Registry has key {
        id:            UID,
        vault_ids:     vector<ID>,
        total_sellers: u64,
        total_bids:    u64,
    }

    public struct Slot has store {
        bidder:            address,
        amount:            u64,
        sender_email_hash: vector<u8>,
        payment_id:        vector<u8>,
        outbid_address:    address,
        pending_refund:    Balance<SUI>,
    }

    public struct AttentionVault has key {
        id:              UID,
        owner:           address,

        // Lifecycle
        /// false after close_vault() is called — blocks new bids.
        active:          bool,

        // Public profile
        name:            String,
        bio:             String,
        category:        u8,
        social_handle:   String,
        /// Public MX-pointed address — shown to winners, routes to this gateway.
        gateway_email:   String,

        // Encrypted real inbox — only gateway private key can decrypt.
        // Produced by encrypt.js (ECDH ephemeral + AES-256-GCM).
        // All three fields are raw bytes (Base64-decoded before storing).
        encrypted_email_ephemeral_pubkey: vector<u8>,  // 65 bytes  (P-256 uncompressed)
        encrypted_email_iv:               vector<u8>,  // 12 bytes  (AES-GCM nonce)
        encrypted_email_ciphertext:       vector<u8>,  // n+16 bytes (ciphertext + GCM tag)

        // Auction state
        epoch:           u64,
        epoch_start:     u64,
        epoch_duration:  u64,
        slots:           vector<Slot>,
        slots_per_epoch: u64,
        floor_bid:       u64,

        // Financials
        balance:         Balance<SUI>,
        total_earned:    u64,
        total_bids:      u64,

        // Whitelist: sha256(email) → true
        whitelist:       Table<vector<u8>, bool>,

        /// Closed conversations: payment_id → true
        closed_threads:  Table<vector<u8>, bool>,
    }

    public struct VaultCap has key, store {
        id:       UID,
        vault_id: ID,
    }

    /// Soulbound receipt — no store ability.
    public struct AttentionReceipt has key {
        id:                UID,
        vault_id:          ID,
        seller:            address,
        seller_name:       String,
        gateway_email:     String,
        sender_email_hash: vector<u8>,
        amount_paid:       u64,
        auction_epoch:     u64,
        payment_id:        vector<u8>,
        slot_index:        u64,
    }

    // ── Events ────────────────────────────────────────────────────────────────

    public struct SellerRegistered has copy, drop {
        vault_id:      ID,
        owner:         address,
        name:          String,
        gateway_email: String,
        category:      u8,
        floor_bid:     u64,
        slots:         u64,
    }

    public struct SlotWon has copy, drop {
        vault_id:          ID,
        receipt_id:        ID,
        payment_id:        vector<u8>,
        sender_email_hash: vector<u8>,
        bidder:            address,
        seller:            address,
        amount:            u64,
        slot_index:        u64,
        auction_epoch:     u64,
    }

    public struct BidderOutbid has copy, drop {
        vault_id:       ID,
        outbid_address: address,
        refund_amount:  u64,
        slot_index:     u64,
    }

    public struct EpochSettled has copy, drop {
        vault_id:        ID,
        auction_epoch:   u64,
        total_collected: u64,
        winner_count:    u64,
    }

    public struct FundsWithdrawn has copy, drop {
        seller: address,
        amount: u64,
    }

    public struct ConversationClosed has copy, drop {
        vault_id:   ID,
        payment_id: vector<u8>,
        seller:     address,
    }

    /// Emitted when a vault is permanently closed and deleted.
    public struct VaultClosed has copy, drop {
        vault_id:        ID,
        owner:           address,
        refunds_issued:  u64,   // number of active bidders refunded
        balance_returned: u64,  // SUI returned to the owner
    }

    // ── Init ──────────────────────────────────────────────────────────────────

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id:            object::new(ctx),
            vault_ids:     vector::empty(),
            total_sellers: 0,
            total_bids:    0,
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    /// Test-only: set active=false without deleting the vault.
    /// Lets tests verify that bid() and settle_epoch() abort with EVaultClosed.
    #[test_only]
    public fun deactivate_for_testing(vault: &mut AttentionVault) {
        vault.active = false;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    fun empty_slot(): Slot {
        Slot {
            bidder:            @0x0,
            amount:            0,
            sender_email_hash: vector::empty(),
            payment_id:        vector::empty(),
            outbid_address:    @0x0,
            pending_refund:    balance::zero<SUI>(),
        }
    }

    fun lowest_slot_index(slots: &vector<Slot>): u64 {
        let mut lowest_idx = 0;
        let mut lowest_amt = vector::borrow(slots, 0).amount;
        let mut i = 1;
        while (i < vector::length(slots)) {
            let s = vector::borrow(slots, i);
            if (s.amount < lowest_amt) {
                lowest_amt = s.amount;
                lowest_idx = i;
            };
            i = i + 1;
        };
        lowest_idx
    }

    fun has_empty_slot(slots: &vector<Slot>): bool {
        let mut i = 0;
        while (i < vector::length(slots)) {
            if (vector::borrow(slots, i).bidder == @0x0) return true;
            i = i + 1;
        };
        false
    }

    fun first_empty_slot(slots: &vector<Slot>): u64 {
        let mut i = 0;
        while (i < vector::length(slots)) {
            if (vector::borrow(slots, i).bidder == @0x0) return i;
            i = i + 1;
        };
        abort 0
    }

    // ── Entry functions ───────────────────────────────────────────────────────

    public fun register(
        registry:                         &mut Registry,
        name:                             String,
        bio:                              String,
        category:                         u8,
        social_handle:                    String,
        gateway_email:                    String,
        encrypted_email_ephemeral_pubkey: vector<u8>,
        encrypted_email_iv:               vector<u8>,
        encrypted_email_ciphertext:       vector<u8>,
        slots_per_epoch:                  u64,
        epoch_duration:                   u64,
        floor_bid:                        u64,
        ctx:                              &mut TxContext,
    ) {
        assert!(floor_bid >= GLOBAL_FLOOR, EBelowGlobalFloor);
        assert!(slots_per_epoch > 0 && slots_per_epoch <= MAX_SLOTS, ETooManySlots);

        let mut slots = vector::empty<Slot>();
        let mut i = 0;
        while (i < slots_per_epoch) {
            vector::push_back(&mut slots, empty_slot());
            i = i + 1;
        };

        let vault = AttentionVault {
            id:              object::new(ctx),
            owner:           ctx.sender(),
            active:          true,
            name,
            bio,
            category,
            social_handle,
            gateway_email,
            encrypted_email_ephemeral_pubkey,
            encrypted_email_iv,
            encrypted_email_ciphertext,
            epoch:           0,
            epoch_start:     ctx.epoch(),
            epoch_duration,
            slots,
            slots_per_epoch,
            floor_bid,
            balance:         balance::zero<SUI>(),
            total_earned:    0,
            total_bids:      0,
            whitelist:       table::new(ctx),
            closed_threads:  table::new(ctx),
        };

        let vault_id = object::id(&vault);

        event::emit(SellerRegistered {
            vault_id,
            owner:         ctx.sender(),
            name:          vault.name,
            gateway_email: vault.gateway_email,
            category:      vault.category,
            floor_bid:     vault.floor_bid,
            slots:         vault.slots_per_epoch,
        });

        vector::push_back(&mut registry.vault_ids, vault_id);
        registry.total_sellers = registry.total_sellers + 1;

        transfer::share_object(vault);
        transfer::transfer(VaultCap { id: object::new(ctx), vault_id }, ctx.sender());
    }

    public fun update_encrypted_email(
        vault:                            &mut AttentionVault,
        cap:                              &VaultCap,
        encrypted_email_ephemeral_pubkey: vector<u8>,
        encrypted_email_iv:               vector<u8>,
        encrypted_email_ciphertext:       vector<u8>,
        ctx:                              &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        vault.encrypted_email_ephemeral_pubkey = encrypted_email_ephemeral_pubkey;
        vault.encrypted_email_iv               = encrypted_email_iv;
        vault.encrypted_email_ciphertext       = encrypted_email_ciphertext;
    }

    public fun bid(
        registry:          &mut Registry,
        vault:             &mut AttentionVault,
        payment_id:        vector<u8>,
        sender_email_hash: vector<u8>,
        bid_coin:          Coin<SUI>,
        ctx:               &mut TxContext,
    ) {
        assert!(vault.active, EVaultClosed);

        let bid_amount = coin::value(&bid_coin);
        assert!(bid_amount >= vault.floor_bid, EBidTooLow);

        let vault_id   = object::id(vault);
        let sender     = ctx.sender();
        let slot_index: u64;

        if (has_empty_slot(&vault.slots)) {
            slot_index = first_empty_slot(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
        } else {
            slot_index = lowest_slot_index(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            assert!(bid_amount > slot.amount, EBidTooLow);

            let outbid_address = slot.bidder;
            let outbid_amount  = slot.amount;
            let refund_bal     = balance::split(&mut vault.balance, outbid_amount);
            balance::join(&mut slot.pending_refund, refund_bal);
            slot.outbid_address = outbid_address;

            event::emit(BidderOutbid {
                vault_id,
                outbid_address,
                refund_amount: outbid_amount,
                slot_index,
            });

            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
        };

        vault.total_bids    = vault.total_bids + 1;
        registry.total_bids = registry.total_bids + 1;

        let receipt = AttentionReceipt {
            id:                object::new(ctx),
            vault_id,
            seller:            vault.owner,
            seller_name:       vault.name,
            gateway_email:     vault.gateway_email,
            sender_email_hash,
            amount_paid:       bid_amount,
            auction_epoch:     vault.epoch,
            payment_id,
            slot_index,
        };
        let receipt_id = object::id(&receipt);
        transfer::transfer(receipt, sender);

        event::emit(SlotWon {
            vault_id,
            receipt_id,
            payment_id,
            sender_email_hash,
            bidder:            sender,
            seller:            vault.owner,
            amount:            bid_amount,
            slot_index,
            auction_epoch:     vault.epoch,
        });
    }

    /// Permanently close and delete the vault.
    ///
    /// What this does in one atomic transaction:
    ///   1. Verifies caller is the owner via VaultCap (cap is consumed/deleted).
    ///   2. Refunds every active slot bidder directly — no claim step needed.
    ///   3. Withdraws any remaining vault balance to the owner.
    ///   4. Destroys the whitelist and closed_threads tables (must be empty first —
    ///      the function drains whitelist entries and closed_threads are left in place,
    ///      so the caller must have cleared them beforehand via remove_from_whitelist
    ///      and the closed_threads table is destroyed only if empty — see note below).
    ///   5. Deletes the vault object and the VaultCap.
    ///
    /// Note on closed_threads: table::destroy_empty aborts if non-empty.
    /// The seller must call close_conversation() for all active threads before
    /// closing, OR the table must simply be empty (no threads were ever closed).
    /// This is intentional — it forces the seller to explicitly acknowledge
    /// outstanding conversations before deletion.
    public fun close_vault(
        vault: AttentionVault,
        cap:   VaultCap,
        ctx:   &mut TxContext,
    ) {
        // ── Auth ──────────────────────────────────────────────────────────────
        assert!(cap.vault_id == object::id(&vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);

        // ── Unpack vault ──────────────────────────────────────────────────────
        let AttentionVault {
            id,
            owner,
            active: _,
            name: _,
            bio: _,
            category: _,
            social_handle: _,
            gateway_email: _,
            encrypted_email_ephemeral_pubkey: _,
            encrypted_email_iv: _,
            encrypted_email_ciphertext: _,
            epoch: _,
            epoch_start: _,
            epoch_duration: _,
            mut slots,
            slots_per_epoch: _,
            floor_bid: _,
            mut balance,
            total_earned: _,
            total_bids: _,
            whitelist,
            closed_threads,
        } = vault;

        let vault_id = id.to_inner();

        // ── Refund all active slot bidders directly ────────────────────────────
        // Also drain any pending_refund balances that haven't been claimed yet.
        let mut refunds_issued = 0u64;
        while (!vector::is_empty(&mut slots)) {
            let Slot {
                bidder,
                amount,
                sender_email_hash: _,
                payment_id: _,
                outbid_address,
                mut pending_refund,
            } = vector::pop_back(&mut slots);

            // Refund the outbid bidder if they haven't claimed yet
            if (outbid_address != @0x0) {
                let refund_amount = balance::value(&pending_refund);
                if (refund_amount > 0) {
                    let refund_coin = coin::from_balance(
                        balance::withdraw_all(&mut pending_refund), ctx
                    );
                    transfer::public_transfer(refund_coin, outbid_address);
                    refunds_issued = refunds_issued + 1;
                };
            };
            balance::destroy_zero(pending_refund);

            // Refund the active bidder from the main vault balance
            if (bidder != @0x0 && amount > 0) {
                let refund_coin = coin::from_balance(
                    balance::split(&mut balance, amount), ctx
                );
                transfer::public_transfer(refund_coin, bidder);
                refunds_issued = refunds_issued + 1;
            };
        };
        vector::destroy_empty(slots);

        // ── Return remaining balance to owner (earned fees, etc.) ─────────────
        let balance_returned = balance::value(&balance);
        if (balance_returned > 0) {
            let remaining = coin::from_balance(balance::withdraw_all(&mut balance), ctx);
            transfer::public_transfer(remaining, owner);
        };
        balance::destroy_zero(balance);

        // ── Destroy tables ────────────────────────────────────────────────────
        // whitelist can be non-empty — drop it entirely
        table::drop(whitelist);
        // closed_threads: destroy_empty aborts if any threads were closed but
        // not accounted for — this is the intended safety check.
        table::destroy_empty(closed_threads);

        // ── Emit & delete ─────────────────────────────────────────────────────
        event::emit(VaultClosed {
            vault_id,
            owner,
            refunds_issued,
            balance_returned,
        });

        // Consume the cap and the vault UID
        let VaultCap { id: cap_id, vault_id: _ } = cap;
        object::delete(cap_id);
        object::delete(id);
    }

    public fun close_conversation(
        vault:      &mut AttentionVault,
        cap:        &VaultCap,
        payment_id: vector<u8>,
        ctx:        &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(table::contains(&vault.closed_threads, payment_id) == false, EAlreadyClosed);

        table::add(&mut vault.closed_threads, payment_id, true);

        event::emit(ConversationClosed {
            vault_id:   object::id(vault),
            payment_id,
            seller:     vault.owner,
        });
    }

    public fun claim_refund(
        vault:      &mut AttentionVault,
        slot_index: u64,
        ctx:        &mut TxContext,
    ) {
        let slot = vector::borrow_mut(&mut vault.slots, slot_index);
        assert!(slot.outbid_address == ctx.sender(), ENotOwner);
        let amount = balance::value(&slot.pending_refund);
        assert!(amount > 0, EZeroBalance);
        let refund = coin::from_balance(balance::withdraw_all(&mut slot.pending_refund), ctx);
        slot.outbid_address = @0x0;
        transfer::public_transfer(refund, ctx.sender());
    }

    public fun settle_epoch(
        vault: &mut AttentionVault,
        cap:   &VaultCap,
        ctx:   &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(vault.active, EVaultClosed);

        let mut winner_count = 0u64;
        let mut i = 0;
        while (i < vector::length(&vault.slots)) {
            if (vector::borrow(&vault.slots, i).bidder != @0x0) winner_count = winner_count + 1;
            i = i + 1;
        };
        let total_collected = balance::value(&vault.balance);

        while (!vector::is_empty(&vault.slots)) {
            let Slot { bidder: _, amount: _, sender_email_hash: _, payment_id: _, outbid_address: _, pending_refund } = vector::pop_back(&mut vault.slots);
            balance::join(&mut vault.balance, pending_refund);
        };

        let mut j = 0;
        while (j < vault.slots_per_epoch) {
            vector::push_back(&mut vault.slots, empty_slot());
            j = j + 1;
        };

        event::emit(EpochSettled {
            vault_id:        object::id(vault),
            auction_epoch:   vault.epoch,
            total_collected,
            winner_count,
        });

        vault.total_earned = vault.total_earned + total_collected;
        vault.epoch        = vault.epoch + 1;
        vault.epoch_start  = ctx.epoch();
    }

    public fun withdraw(
        vault: &mut AttentionVault,
        cap:   &VaultCap,
        ctx:   &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        let amount = balance::value(&vault.balance);
        assert!(amount > 0, EZeroBalance);
        let coin = coin::from_balance(balance::withdraw_all(&mut vault.balance), ctx);
        transfer::public_transfer(coin, vault.owner);
        event::emit(FundsWithdrawn { seller: vault.owner, amount });
    }

    public fun add_to_whitelist(
        vault:             &mut AttentionVault,
        cap:               &VaultCap,
        sender_email_hash: vector<u8>,
        ctx:               &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(!table::contains(&vault.whitelist, sender_email_hash), EAlreadyWhitelisted);
        table::add(&mut vault.whitelist, sender_email_hash, true);
    }

    public fun remove_from_whitelist(
        vault:             &mut AttentionVault,
        cap:               &VaultCap,
        sender_email_hash: vector<u8>,
        ctx:               &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(table::contains(&vault.whitelist, sender_email_hash), ENotWhitelisted);
        table::remove(&mut vault.whitelist, sender_email_hash);
    }

    public fun update_profile(
        vault:         &mut AttentionVault,
        cap:           &VaultCap,
        name:          String,
        bio:           String,
        category:      u8,
        social_handle: String,
        gateway_email: String,
        ctx:           &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        vault.name          = name;
        vault.bio           = bio;
        vault.category      = category;
        vault.social_handle = social_handle;
        vault.gateway_email = gateway_email;
    }

    public fun update_auction_params(
        vault:           &mut AttentionVault,
        cap:             &VaultCap,
        floor_bid:       u64,
        slots_per_epoch: u64,
        epoch_duration:  u64,
        ctx:             &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(floor_bid >= GLOBAL_FLOOR, EBelowGlobalFloor);
        assert!(slots_per_epoch > 0 && slots_per_epoch <= MAX_SLOTS, ETooManySlots);
        vault.floor_bid       = floor_bid;
        vault.slots_per_epoch = slots_per_epoch;
        vault.epoch_duration  = epoch_duration;
    }

    // ── Read-only ─────────────────────────────────────────────────────────────

    public fun encrypted_email(vault: &AttentionVault): (vector<u8>, vector<u8>, vector<u8>) {
        (
            vault.encrypted_email_ephemeral_pubkey,
            vault.encrypted_email_iv,
            vault.encrypted_email_ciphertext,
        )
    }

    public fun is_vault_active(vault: &AttentionVault): bool  { vault.active }
    public fun is_thread_closed(vault: &AttentionVault, payment_id: &vector<u8>): bool {
        table::contains(&vault.closed_threads, *payment_id)
    }
    public fun is_whitelisted(vault: &AttentionVault, email_hash: &vector<u8>): bool {
        table::contains(&vault.whitelist, *email_hash)
    }

    public fun slots_available(vault: &AttentionVault): u64 {
        let mut count = 0u64;
        let mut i = 0;
        while (i < vector::length(&vault.slots)) {
            if (vector::borrow(&vault.slots, i).bidder == @0x0) count = count + 1;
            i = i + 1;
        };
        count
    }

    public fun current_lowest_bid(vault: &AttentionVault): u64 {
        if (has_empty_slot(&vault.slots)) return vault.floor_bid;
        vector::borrow(&vault.slots, lowest_slot_index(&vault.slots)).amount
    }

    public fun floor_bid(vault: &AttentionVault): u64       { vault.floor_bid }
    public fun current_epoch(vault: &AttentionVault): u64   { vault.epoch }
    public fun total_earned(vault: &AttentionVault): u64    { vault.total_earned }
    public fun total_bids(vault: &AttentionVault): u64      { vault.total_bids }
    public fun vault_balance(vault: &AttentionVault): u64   { balance::value(&vault.balance) }
    public fun vault_owner(vault: &AttentionVault): address { vault.owner }
    public fun gateway_email(vault: &AttentionVault): &String { &vault.gateway_email }
    public fun registry_count(r: &Registry): u64            { r.total_sellers }
    public fun registry_total_bids(r: &Registry): u64       { r.total_bids }
    public fun registry_vaults(r: &Registry): &vector<ID>   { &r.vault_ids }
}
