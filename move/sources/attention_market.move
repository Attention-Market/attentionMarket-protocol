/// AttentionMarket — Attention auction marketplace on Sui
///
/// Slot model:
///   - Seller creates a vault with X slots per epoch and a floor bid.
///   - Bidders compete for slots. If slots are full, a higher bid displaces
///     the lowest current holder, who is refunded immediately on-chain.
///   - Seller manually settles the epoch: AttentionReceipt is minted to every
///     winner, slots reset, epoch increments, and collected funds (minus
///     platform fee) are transferred directly to the vault owner.
///   - Winners use their AttentionReceipt to sign a delivery token on the
///     frontend at any time.
///   - Seller can close a specific conversation via close_conversation(), which
///     invalidates that payment_id at the gateway permanently.
///   - Bids that remain unsettled for 10+ epochs beyond their auction epoch
///     can be refunded by anyone calling refund_expired_bids().
///
/// Fee model:
///   - A platform fee (basis points, max 1000 = 10%) is set on the Registry
///     by the holder of the PlatformCap (the deployer).
///   - Fee is deducted from proceeds at settle_epoch() and withdraw() and
///     sent to the fee_recipient address stored on the Registry.
///   - fee_bps = 0 means no fee is taken.
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
    const GLOBAL_FLOOR:        u64 = 1_000_000;  // 0.001 SUI
    const MAX_SLOTS:           u64 = 100;
    const REFUND_AFTER_EPOCHS: u64 = 10;
    const MAX_FEE_BPS:         u64 = 1_000;      // 10%
    const BPS_DENOM:           u64 = 10_000;

    // ── Errors ────────────────────────────────────────────────────────────────
    const ENotOwner:              u64 = 1;
    const EBidTooLow:             u64 = 2;
    const EBelowGlobalFloor:      u64 = 3;
    const EZeroBalance:           u64 = 4;
    const ETooManySlots:          u64 = 5;
    const EAlreadyClosed:         u64 = 8;
    const EVaultClosed:           u64 = 9;
    const EDuplicateGatewayEmail: u64 = 10;
    /// Bid rejected — the epoch bidding window has closed; seller must settle first.
    const EEpochExpired:          u64 = 11;
    /// Settle rejected — the epoch bidding window is still open.
    const EEpochNotOver:          u64 = 12;
    /// Proposed fee exceeds the 10% platform cap.
    const EFeeTooHigh:            u64 = 13;

    // ── Structs ───────────────────────────────────────────────────────────────

    /// Capability held by the deployer. Required to update fee_bps or
    /// fee_recipient on the Registry.
    public struct PlatformCap has key, store {
        id: UID,
    }

    public struct Registry has key {
        id:             UID,
        vault_ids:      vector<ID>,
        total_sellers:  u64,
        total_bids:     u64,
        gateway_emails: Table<String, ID>,
        /// Platform fee in basis points (0–1000). Set by PlatformCap holder.
        fee_bps:        u64,
        /// Address that receives platform fees.
        fee_recipient:  address,
    }

    /// One auction slot. Overbid refunds are immediate — no pending state.
    public struct Slot has store {
        bidder:            address,
        amount:            u64,
        sender_email_hash: vector<u8>,
        payment_id:        vector<u8>,
        /// The vault epoch in which this bid was placed (for expiry checks).
        bid_epoch:         u64,
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

    public struct BidExpiredRefund has copy, drop {
        vault_id:      ID,
        bidder:        address,
        refund_amount: u64,
        slot_index:    u64,
        bid_epoch:     u64,
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
        fee_taken:       u64,
        seller_received: u64,
        winner_count:    u64,
    }

    public struct FundsWithdrawn has copy, drop {
        seller:          address,
        amount:          u64,
        fee_taken:       u64,
        seller_received: u64,
    }

    public struct FeeUpdated has copy, drop {
        old_fee_bps:    u64,
        new_fee_bps:    u64,
        fee_recipient:  address,
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
        // PlatformCap goes to the deployer — they alone control fee settings.
        transfer::transfer(PlatformCap { id: object::new(ctx) }, ctx.sender());

        transfer::share_object(Registry {
            id:             object::new(ctx),
            vault_ids:      vector::empty(),
            total_sellers:  0,
            total_bids:     0,
            gateway_emails: table::new(ctx),
            fee_bps:        0,          // no fee by default
            fee_recipient:  ctx.sender(),
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
            bid_epoch:         0,
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

    /// Split `amount` into (fee, remainder) using the registry's fee_bps.
    /// fee = amount * fee_bps / 10_000, rounded down.
    fun compute_fee(amount: u64, fee_bps: u64): (u64, u64) {
        let fee = amount * fee_bps / BPS_DENOM;
        (fee, amount - fee)
    }

    /// Deduct fee from vault balance, send fee to recipient, return net amount.
    fun deduct_and_send_fee(
        vault:         &mut AttentionVault,
        total:         u64,
        fee_bps:       u64,
        fee_recipient: address,
        ctx:           &mut TxContext,
    ): (u64, u64) {
        let (fee, net) = compute_fee(total, fee_bps);
        if (fee > 0) {
            let fee_coin = coin::from_balance(
                balance::split(&mut vault.balance, fee), ctx
            );
            transfer::public_transfer(fee_coin, fee_recipient);
        };
        (fee, net)
    }

    /// Refund and clear any slot whose bid is at least REFUND_AFTER_EPOCHS old.
    fun sweep_expired_slots(
        vault:         &mut AttentionVault,
        current_epoch: u64,
        ctx:           &mut TxContext,
    ): u64 {
        let vault_id = object::id(vault);
        let mut freed = 0u64;
        let mut i = 0;
        while (i < vector::length(&vault.slots)) {
            let slot = vector::borrow(&vault.slots, i);
            if (slot.bidder != @0x0
                && slot.amount > 0
                && current_epoch >= slot.bid_epoch + REFUND_AFTER_EPOCHS)
            {
                let bidder        = slot.bidder;
                let refund_amount = slot.amount;
                let bid_epoch     = slot.bid_epoch;

                let refund = coin::from_balance(
                    balance::split(&mut vault.balance, refund_amount), ctx
                );
                transfer::public_transfer(refund, bidder);

                event::emit(BidExpiredRefund {
                    vault_id,
                    bidder,
                    refund_amount,
                    slot_index: i,
                    bid_epoch,
                });

                let s = vector::borrow_mut(&mut vault.slots, i);
                s.bidder            = @0x0;
                s.amount            = 0;
                s.sender_email_hash = vector::empty();
                s.payment_id        = vector::empty();
                s.bid_epoch         = 0;

                freed = freed + 1;
            };
            i = i + 1;
        };
        freed
    }

    // ── Entry functions ───────────────────────────────────────────────────────

    /// Update the platform fee. Only the PlatformCap holder can call this.
    /// fee_bps must be ≤ 1000 (10%). Set fee_recipient to wherever fees go.
    public fun set_fee(
        registry:      &mut Registry,
        _cap:          &PlatformCap,
        fee_bps:       u64,
        fee_recipient: address,
    ) {
        assert!(fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
        let old = registry.fee_bps;
        registry.fee_bps       = fee_bps;
        registry.fee_recipient = fee_recipient;
        event::emit(FeeUpdated { old_fee_bps: old, new_fee_bps: fee_bps, fee_recipient });
    }

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
    /// - Expired slots (bid placed 10+ epochs ago) are swept and refunded first.
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
        assert!(ctx.epoch() < vault.epoch_start + vault.epoch_duration, EEpochExpired);

        // Sweep any stale bids before deciding slot availability
        sweep_expired_slots(vault, ctx.epoch(), ctx);

        let bid_amount    = coin::value(&bid_coin);
        assert!(bid_amount >= vault.floor_bid, EBidTooLow);

        let vault_id      = object::id(vault);
        let sender        = ctx.sender();
        let current_epoch = vault.epoch;
        let slot_index: u64;

        if (has_empty_slot(&vault.slots)) {
            slot_index = first_empty_slot(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
            slot.bid_epoch         = current_epoch;
        } else {
            slot_index = lowest_slot_index(&vault.slots);
            let slot = vector::borrow_mut(&mut vault.slots, slot_index);
            assert!(bid_amount > slot.amount, EBidTooLow);

            let outbid_address = slot.bidder;
            let outbid_amount  = slot.amount;

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

            balance::join(&mut vault.balance, coin::into_balance(bid_coin));
            slot.bidder            = sender;
            slot.amount            = bid_amount;
            slot.sender_email_hash = sender_email_hash;
            slot.payment_id        = payment_id;
            slot.bid_epoch         = current_epoch;
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
            auction_epoch: current_epoch,
        });
    }

    /// Manually trigger expired-bid refunds on a vault (callable by anyone).
    public fun refund_expired_bids(
        vault: &mut AttentionVault,
        ctx:   &mut TxContext,
    ) {
        sweep_expired_slots(vault, ctx.epoch(), ctx);
    }

    /// Settle the current epoch.
    /// Mints a soulbound AttentionReceipt to every winning slot holder,
    /// resets all slots, increments epoch. Platform fee is deducted first;
    /// the net amount is transferred directly to the vault owner.
    public fun settle_epoch(
        registry: &Registry,
        vault:    &mut AttentionVault,
        cap:      &VaultCap,
        ctx:      &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        assert!(vault.active, EVaultClosed);
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

        // Clear and refill slots for next epoch
        while (!vector::is_empty(&vault.slots)) {
            let Slot {
                bidder: _,
                amount: _,
                sender_email_hash: _,
                payment_id: _,
                bid_epoch: _,
            } = vector::pop_back(&mut vault.slots);
        };
        let mut j = 0;
        while (j < vault.slots_per_epoch) {
            vector::push_back(&mut vault.slots, empty_slot());
            j = j + 1;
        };

        vault.total_earned = vault.total_earned + total_collected;
        vault.epoch        = vault.epoch + 1;
        vault.epoch_start  = ctx.epoch();

        // Deduct platform fee, then pay seller the remainder
        let (fee_taken, seller_received) = deduct_and_send_fee(
            vault,
            total_collected,
            registry.fee_bps,
            registry.fee_recipient,
            ctx,
        );

        event::emit(EpochSettled {
            vault_id,
            auction_epoch: current_epoch,
            total_collected,
            fee_taken,
            seller_received,
            winner_count,
        });

        if (seller_received > 0) {
            let payout = coin::from_balance(
                balance::withdraw_all(&mut vault.balance), ctx
            );
            transfer::public_transfer(payout, seller);
            event::emit(FundsWithdrawn {
                seller,
                amount:          total_collected,
                fee_taken,
                seller_received,
            });
        };
    }

    /// Withdraw any residual balance (e.g. after expired-bid sweeps).
    /// Platform fee is deducted before paying the seller.
    public fun withdraw(
        registry: &Registry,
        vault:    &mut AttentionVault,
        cap:      &VaultCap,
        ctx:      &mut TxContext,
    ) {
        assert!(cap.vault_id == object::id(vault), ENotOwner);
        assert!(ctx.sender() == vault.owner, ENotOwner);
        let amount = balance::value(&vault.balance);
        assert!(amount > 0, EZeroBalance);

        let (fee_taken, seller_received) = deduct_and_send_fee(
            vault,
            amount,
            registry.fee_bps,
            registry.fee_recipient,
            ctx,
        );

        let coin = coin::from_balance(balance::withdraw_all(&mut vault.balance), ctx);
        transfer::public_transfer(coin, vault.owner);
        event::emit(FundsWithdrawn {
            seller:          vault.owner,
            amount,
            fee_taken,
            seller_received,
        });
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
    /// Any unsettled slot bidders are refunded. No fee on refunds.
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
            closed_threads,
        } = vault;

        let vault_id = id.to_inner();
        let mut refunds_issued = 0u64;

        // Refund active bidders — no fee on refunds
        while (!vector::is_empty(&mut slots)) {
            let Slot {
                bidder,
                amount,
                sender_email_hash: _,
                payment_id: _,
                bid_epoch: _,
            } = vector::pop_back(&mut slots);
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
    public fun floor_bid(vault: &AttentionVault): u64        { vault.floor_bid }
    public fun current_epoch(vault: &AttentionVault): u64    { vault.epoch }
    public fun total_earned(vault: &AttentionVault): u64     { vault.total_earned }
    public fun total_bids(vault: &AttentionVault): u64       { vault.total_bids }
    public fun vault_balance(vault: &AttentionVault): u64    { balance::value(&vault.balance) }
    public fun vault_owner(vault: &AttentionVault): address  { vault.owner }
    public fun gateway_email(vault: &AttentionVault): &String { &vault.gateway_email }
    public fun registry_count(r: &Registry): u64             { r.total_sellers }
    public fun registry_total_bids(r: &Registry): u64        { r.total_bids }
    public fun registry_vaults(r: &Registry): &vector<ID>    { &r.vault_ids }
    public fun registry_email_taken(r: &Registry, email: String): bool {
        table::contains(&r.gateway_emails, email)
    }
    public fun registry_fee_bps(r: &Registry): u64           { r.fee_bps }
    public fun registry_fee_recipient(r: &Registry): address  { r.fee_recipient }
}
