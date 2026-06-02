/// AttentionMarket — Attention auction marketplace on Sui
///
/// Slot model:
///   - Seller creates a vault with X slots per epoch and a floor bid.
///   - Bidders compete for slots. If slots are full, a higher bid displaces
///     the lowest current holder, who is refunded immediately on-chain.
///   - Seller manually settles the epoch: AttentionReceipt is minted to every
///     winner, slots reset, epoch increments.
///   - Winners use their AttentionReceipt to sign a delivery token on the
///     frontend at any time.
///   - Seller can close a specific conversation via close_conversation(), which
///     invalidates that payment_id at the gateway permanently.
///
/// Privacy model:
///   - Seller's real inbox stored as ECDH/AES-GCM encrypted blob only.
///   - gateway_email (public MX address) is public.
///   - Bidder sender email stored/emitted as sha256(email) only.
///   - payment_id = sha256(emailHash + ":" + vaultId)
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
    const ENotOwner:              u64 = 1;
    const EBidTooLow:             u64 = 2;
    const EBelowGlobalFloor:      u64 = 3;
    const EZeroBalance:           u64 = 4;
    const ETooManySlots:          u64 = 5;
    const EAlreadyWhitelisted:    u64 = 6;
    const ENotWhitelisted:        u64 = 7;
    const EAlreadyClosed:         u64 = 8;
    const EVaultClosed:           u64 = 9;
    const EDuplicateGatewayEmail: u64 = 10;
    /// Bid rejected — the epoch bidding window has closed; seller must settle first.
    const EEpochExpired:          u64 = 11;
    /// Settle rejected — the epoch bidding window is still open.
    const EEpochNotOver:          u64 = 12;

    // ── Structs ───────────────────────────────────────────────────────────────

    public struct Registry has key {
        id:             UID,
        vault_ids:      vector<ID>,
        total_sellers:  u64,
        total_bids:     u64,
        gateway_emails: Table<String, ID>,
    }

    /// One auction slot. Overbid refunds are immediate — no pending state.
    public struct Slot has store {
        bidder:            address,
        amount:            u64,
        sender_email_hash: vector<u8>,
        payment_id:        vector<u8>,
    }

    public struct AttentionVault has key {
        id:              UID,
        owner:           address,
        active:          bool,

        // Public profile
        name:            String,
        bio:             String,
        category:        u8,
        social_handle:   String,
        gateway_email:   String,

        // Encrypted real inbox — only gateway private key can decrypt
        encrypted_email_ephemeral_pubkey: vector<u8>,
        encrypted_email_iv:               vector<u8>,
        encrypted_email_ciphertext:       vector<u8>,

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

        whitelist:      Table<vector<u8>, bool>,
        closed_threads: Table<vector<u8>, bool>,
    }

    public struct VaultCap has key, store {
        id:       UID,
        vault_id: ID,
    }

    /// Soulbound receipt minted to each winner at settle_epoch().
    /// No `store` — cannot be transferred.
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

    public struct BidPlaced has copy, drop {
        vault_id:          ID,
        payment_id:        vector<u8>,
        sender_email_hash: vector<u8>,
        bidder:            address,
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

    public struct VaultClosed has copy, drop {
        vault_id:         ID,
        owner:            address,
        refunds_issued:   u64,
        balance_returned: u64,
    }

    // ── Init ──────────────────────────────────────────────────────────────────

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id:             object::new(ctx),
            vault_ids:      vector::empty(),
            total_sellers:  0,
            total_bids:     0,
            gateway_emails: table::new(ctx),
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) { init(ctx); }

    #[test_only]
    public fun deactivate_for_testing(vault: &mut AttentionVault) { vault.active = false; }

    // ── Helpers ───────────────────────────────────────────────────────────────

    fun empty_slot(): Slot {
        Slot {
            bidder:            @0x0,
            amount:            0,
            sender_email_hash: vector::empty(),
            payment_id:        vector::empty(),
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
        assert!(!table::contains(&registry.gateway_emails, gateway_email), EDuplicateGatewayEmail);

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
        table::add(&mut registry.gateway_emails, vault.gateway_email, vault_id);

        transfer::share_object(vault);
        transfer::transfer(VaultCap { id: object::new(ctx), vault_id }, ctx.sender());
    }

    /// Place or improve a bid.
    /// - Empty slot available: fill it immediately.
    /// - All slots full: must beat the lowest bid. The displaced bidder is
    ///   refunded immediately via transfer — no claim step needed.
    public fun bid(
        registry:          &mut Registry,
        vault:             &mut AttentionVault,
        payment_id:        vector<u8>,
        sender_email_hash: vector<u8>,
        bid_coin:          Coin<SUI>,
        ctx:               &mut TxContext,
    ) {
        assert!(vault.active, EVaultClosed);
        // Reject bids once the epoch bidding window has closed
        assert!(ctx.epoch() < vault.epoch_start + vault.epoch_duration, EEpochExpired);

        let bid_amount = coin::value(&bid_coin);
        assert!(bid_amount >= vault.floor_bid, EBidTooLow);

        let vault_id = object::id(vault);
        let sender   = ctx.sender();
        let slot_index: u64;

        if (has_empty_slot(&vault.slots)) {
            // ── Fill an empty slot ────────────────────────────────────────────
            slot_index = first_empty_slot(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
        } else {
            // ── Outbid the lowest slot holder ─────────────────────────────────
            slot_index = lowest_slot_index(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            assert!(bid_amount > slot.amount, EBidTooLow);

            let outbid_address = slot.bidder;
            let outbid_amount  = slot.amount;

            // Refund the displaced bidder immediately — no pending state
            let refund = coin::from_balance(
                balance::split(&mut vault.balance, outbid_amount), ctx
            );
            transfer::public_transfer(refund, outbid_address);

            event::emit(BidderOutbid {
                vault_id,
                outbid_address,
                refund_amount: outbid_amount,
                slot_index,
            });

            // Place the new bid
            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
        };

        vault.total_bids    = vault.total_bids + 1;
        registry.total_bids = registry.total_bids + 1;

        event::emit(BidPlaced {
            vault_id,
            payment_id,
            sender_email_hash,
            bidder:        sender,
            amount:        bid_amount,
            slot_index,
            auction_epoch: vault.epoch,
        });
    }

    /// Settle the current epoch.
    /// Mints a soulbound AttentionReceipt to every winning slot holder,
    /// resets all slots, increments epoch.
    public fun settle_epoch(
        vault: &mut AttentionVault,
        cap:   &VaultCap,
        ctx:   &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(vault.active, EVaultClosed);
        // Only settleable after the epoch bidding window has expired
        assert!(ctx.epoch() >= vault.epoch_start + vault.epoch_duration, EEpochNotOver);

        let vault_id        = object::id(vault);
        let current_epoch   = vault.epoch;
        let seller          = vault.owner;
        let seller_name     = vault.name;
        let gateway_email   = vault.gateway_email;
        let total_collected = balance::value(&vault.balance);
        let mut winner_count = 0u64;

        // Mint a receipt to each winner
        let mut i = 0;
        while (i < vector::length(&vault.slots)) {
            let slot = vector::borrow(&vault.slots, i);
            if (slot.bidder != @0x0) {
                let receipt = AttentionReceipt {
                    id:                object::new(ctx),
                    vault_id,
                    seller,
                    seller_name,
                    gateway_email,
                    sender_email_hash: slot.sender_email_hash,
                    amount_paid:       slot.amount,
                    auction_epoch:     current_epoch,
                    payment_id:        slot.payment_id,
                    slot_index:        i,
                };
                let receipt_id = object::id(&receipt);
                transfer::transfer(receipt, slot.bidder);

                event::emit(SlotWon {
                    vault_id,
                    receipt_id,
                    payment_id:        slot.payment_id,
                    sender_email_hash: slot.sender_email_hash,
                    bidder:            slot.bidder,
                    seller,
                    amount:            slot.amount,
                    slot_index:        i,
                    auction_epoch:     current_epoch,
                });

                winner_count = winner_count + 1;
            };
            i = i + 1;
        };

        // Clear slots — no pending_refund to handle, all refunds were immediate
        while (!vector::is_empty(&vault.slots)) {
            let Slot { bidder: _, amount: _, sender_email_hash: _, payment_id: _ } =
                vector::pop_back(&mut vault.slots);
        };

        // Refill for next epoch
        let mut j = 0;
        while (j < vault.slots_per_epoch) {
            vector::push_back(&mut vault.slots, empty_slot());
            j = j + 1;
        };

        vault.total_earned = vault.total_earned + total_collected;
        vault.epoch        = vault.epoch + 1;
        vault.epoch_start  = ctx.epoch();

        event::emit(EpochSettled {
            vault_id,
            auction_epoch: current_epoch,
            total_collected,
            winner_count,
        });
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

    /// Permanently invalidate a winner's delivery token.
    public fun close_conversation(
        vault:      &mut AttentionVault,
        cap:        &VaultCap,
        payment_id: vector<u8>,
        ctx:        &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(!table::contains(&vault.closed_threads, payment_id), EAlreadyClosed);
        table::add(&mut vault.closed_threads, payment_id, true);
        event::emit(ConversationClosed {
            vault_id:   object::id(vault),
            payment_id,
            seller:     vault.owner,
        });
    }

    /// Permanently close and delete the vault.
    /// Any unsettled slot bidders in the current epoch are refunded immediately.
    /// closed_threads table must be empty — settle all epochs first.
    public fun close_vault(
        registry: &mut Registry,
        vault:    AttentionVault,
        cap:      VaultCap,
        ctx:      &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(&vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);

        let AttentionVault {
            id,
            owner,
            active: _,
            name: _,
            bio: _,
            category: _,
            social_handle: _,
            gateway_email,
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
        let mut refunds_issued = 0u64;

        // Refund any active bidders in the unsettled current epoch
        while (!vector::is_empty(&mut slots)) {
            let Slot { bidder, amount, sender_email_hash: _, payment_id: _ } =
                vector::pop_back(&mut slots);
            if (bidder != @0x0 && amount > 0) {
                let refund = coin::from_balance(balance::split(&mut balance, amount), ctx);
                transfer::public_transfer(refund, bidder);
                refunds_issued = refunds_issued + 1;
            };
        };
        vector::destroy_empty(slots);

        let balance_returned = balance::value(&balance);
        if (balance_returned > 0) {
            let remaining = coin::from_balance(balance::withdraw_all(&mut balance), ctx);
            transfer::public_transfer(remaining, owner);
        };
        balance::destroy_zero(balance);

        table::drop(whitelist);
        table::destroy_empty(closed_threads);

        if (table::contains(&registry.gateway_emails, gateway_email)) {
            table::remove(&mut registry.gateway_emails, gateway_email);
        };

        event::emit(VaultClosed {
            vault_id,
            owner,
            refunds_issued,
            balance_returned,
        });

        let VaultCap { id: cap_id, vault_id: _ } = cap;
        object::delete(cap_id);
        object::delete(id);
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
        registry:      &mut Registry,
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
        if (gateway_email != vault.gateway_email) {
            assert!(!table::contains(&registry.gateway_emails, gateway_email), EDuplicateGatewayEmail);
            table::remove(&mut registry.gateway_emails, vault.gateway_email);
            table::add(&mut registry.gateway_emails, gateway_email, object::id(vault));
        };
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
        (vault.encrypted_email_ephemeral_pubkey, vault.encrypted_email_iv, vault.encrypted_email_ciphertext)
    }
    public fun is_vault_active(vault: &AttentionVault): bool { vault.active }
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
    public fun registry_count(r: &Registry): u64          { r.total_sellers }
    public fun registry_total_bids(r: &Registry): u64     { r.total_bids }
    public fun registry_vaults(r: &Registry): &vector<ID> { &r.vault_ids }
    public fun registry_email_taken(r: &Registry, email: String): bool {
        table::contains(&r.gateway_emails, email)
    }
}
