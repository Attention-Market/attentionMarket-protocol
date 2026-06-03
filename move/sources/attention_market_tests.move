#[test_only]
module attentionmarket::attention_market_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_utils::assert_eq;
    use std::string;

    use attentionmarket::attention_market::{
        Self,
        Registry,
        AttentionVault,
        VaultCap,
        AttentionReceipt,
    };

    // ── Test addresses ────────────────────────────────────────────────────────
    const SELLER:  address = @0xAA;
    const BIDDER1: address = @0xBB;
    const BIDDER2: address = @0xCC;
    const RANDO:   address = @0xDD;

    // ── Dummy encrypted email blobs ───────────────────────────────────────────
    fun dummy_ephemeral_pubkey(): vector<u8> { vector[
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ] }
    fun dummy_iv(): vector<u8> { vector[0,0,0,0,0,0,0,0,0,0,0,0] }
    fun dummy_ciphertext(): vector<u8> { vector[
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ] }

    // ── Shared helpers ────────────────────────────────────────────────────────

    /// Sets up a vault with epoch_duration = 1 so a single next_epoch() call
    /// is enough to open the settle window in most tests.
    fun setup_vault(): Scenario {
        let mut scenario = ts::begin(SELLER);
        {
            attention_market::init_for_testing(ts::ctx(&mut scenario));
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Alice"),
                string::utf8(b"Bio"),
                1,
                string::utf8(b"@alice"),
                string::utf8(b"alice@gateway.example"),
                dummy_ephemeral_pubkey(),
                dummy_iv(),
                dummy_ciphertext(),
                3,         // slots_per_epoch
                1,         // epoch_duration = 1 (one next_epoch() to unlock settle)
                1_000_000, // floor_bid = GLOBAL_FLOOR
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        scenario
    }

    /// Advance the Sui epoch n times, staying as sender.
    fun advance_epochs(scenario: &mut Scenario, sender: address, n: u64) {
        let mut i = 0;
        while (i < n) {
            ts::next_epoch(scenario, sender);
            i = i + 1;
        };
    }

    fun do_bid(
        scenario:   &mut Scenario,
        bidder:     address,
        amount:     u64,
        payment_id: vector<u8>,
        email_hash: vector<u8>,
    ) {
        ts::next_tx(scenario, bidder);
        {
            let mut registry = ts::take_shared<Registry>(scenario);
            let mut vault    = ts::take_shared<AttentionVault>(scenario);
            let coin         = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
            attention_market::bid(
                &mut registry,
                &mut vault,
                payment_id,
                email_hash,
                coin,
                ts::ctx(scenario),
            );
            ts::return_shared(registry);
            ts::return_shared(vault);
        };
    }

    /// Settle the current epoch (caller must have already advanced past epoch_duration).
    fun do_settle(scenario: &mut Scenario) {
        ts::next_tx(scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(scenario);
            let cap       = ts::take_from_address<VaultCap>(scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1. register
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_register_creates_vault_and_cap() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let registry = ts::take_shared<Registry>(&scenario);
            assert_eq(attention_market::registry_count(&registry), 1);
            assert_eq(vector::length(attention_market::registry_vaults(&registry)), 1);
            ts::return_shared(registry);

            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::floor_bid(&vault),       1_000_000);
            assert_eq(attention_market::current_epoch(&vault),   0);
            assert_eq(attention_market::total_earned(&vault),    0);
            assert_eq(attention_market::total_bids(&vault),      0);
            assert_eq(attention_market::vault_balance(&vault),   0);
            assert_eq(attention_market::slots_available(&vault), 3);
            assert_eq(attention_market::vault_owner(&vault),     SELLER);
            assert!(attention_market::is_vault_active(&vault),   0);
            ts::return_shared(vault);

            assert!(ts::has_most_recent_for_address<VaultCap>(SELLER), 0);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_register_stores_encrypted_email() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let (epk, iv, ct) = attention_market::encrypted_email(&vault);
            assert_eq(vector::length(&epk), 65);
            assert_eq(vector::length(&iv),  12);
            assert_eq(vector::length(&ct),  32);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EBelowGlobalFloor)]
    fun test_register_floor_below_global_floor_fails() {
        let mut scenario = ts::begin(SELLER);
        attention_market::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Alice"), string::utf8(b"Bio"),
                1, string::utf8(b"@alice"), string::utf8(b"alice@gw"),
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                3, 1, 999_999,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ETooManySlots)]
    fun test_register_zero_slots_fails() {
        let mut scenario = ts::begin(SELLER);
        attention_market::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Alice"), string::utf8(b"Bio"),
                1, string::utf8(b"@alice"), string::utf8(b"alice@gw"),
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                0, 1, 1_000_000,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ETooManySlots)]
    fun test_register_too_many_slots_fails() {
        let mut scenario = ts::begin(SELLER);
        attention_market::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Alice"), string::utf8(b"Bio"),
                1, string::utf8(b"@alice"), string::utf8(b"alice@gw"),
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                101, 1, 1_000_000,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. bid — happy paths
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_bid_fills_empty_slot() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let vault    = ts::take_shared<AttentionVault>(&scenario);
            let registry = ts::take_shared<Registry>(&scenario);
            assert_eq(attention_market::slots_available(&vault),        2);
            assert_eq(attention_market::vault_balance(&vault),          1_000_000);
            assert_eq(attention_market::total_bids(&vault),             1);
            assert_eq(attention_market::registry_total_bids(&registry), 1);
            ts::return_shared(vault);
            ts::return_shared(registry);
            // No receipt yet — receipts only mint at settle_epoch
        };
        ts::end(scenario);
    }

    #[test]
    fun test_bid_fills_all_slots() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::slots_available(&vault), 0);
            assert_eq(attention_market::vault_balance(&vault),   6_000_000);
            assert_eq(attention_market::total_bids(&vault),      3);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_bid_current_lowest_bid_with_empty_slots_returns_floor() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_lowest_bid(&vault), 1_000_000);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_bid_current_lowest_bid_full_slots_returns_lowest_bid() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 5_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_lowest_bid(&vault), 1_000_000);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_bid_outbids_lowest_slot_and_refunds_immediately() {
        // Fill all 3 slots then outbid BIDDER1 (lowest). BIDDER1 gets a coin
        // immediately — no claim step needed.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        do_bid(&mut scenario, SELLER,  4_000_000, b"pid4", b"hash4");

        ts::next_tx(&mut scenario, BIDDER1);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::slots_available(&vault), 0);
            assert_eq(attention_market::vault_balance(&vault),   9_000_000);
            ts::return_shared(vault);
            assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3. bid — failure paths
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = attention_market::EBidTooLow)]
    fun test_bid_below_floor_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 999_999, b"pid", b"hash");
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EBidTooLow)]
    fun test_bid_does_not_beat_lowest_slot_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   4_000_000, b"pid3", b"hash3");
        do_bid(&mut scenario, SELLER,  2_000_000, b"pid4", b"hash4");
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EEpochExpired)]
    fun test_bid_after_epoch_window_closed_fails() {
        let mut scenario = setup_vault();
        // Advance past the epoch_duration=1 window
        advance_epochs(&mut scenario, SELLER, 1);
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. refund_expired_bids
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_refund_expired_bids_clears_stale_slot() {
        // bid_epoch is stored as vault.epoch (= 0). Expiry fires when
        // ctx.epoch() >= bid_epoch + 10, i.e. Sui epoch >= 10.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");

        // Advance 10 Sui epochs to cross the expiry threshold
        advance_epochs(&mut scenario, RANDO, 10);

        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::refund_expired_bids(&mut vault, ts::ctx(&mut scenario));
            // The one occupied slot was swept; all 3 are now empty
            assert_eq(attention_market::slots_available(&vault), 3);
            assert_eq(attention_market::vault_balance(&vault),   0);
            ts::return_shared(vault);
        };

        ts::next_tx(&mut scenario, BIDDER1);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0); };

        ts::end(scenario);
    }

    #[test]
    fun test_bid_sweeps_expired_slots_before_placing() {
        // Fill all 3 slots in epoch 0, let them age past the 10-epoch expiry
        // threshold, settle to reopen the bidding window, then place a new
        // floor bid. The sweep inside bid() should free the stale slots so the
        // new bid lands without needing to outbid anyone.
        //
        // Timeline (Sui epochs):
        //   0  — bids placed (bid_epoch = vault.epoch = 0)
        //   1  — advance past epoch_duration=1; settle epoch 0
        //        (epoch_start resets to 1, bidding window is now 1..2)
        //  11  — advance 10 more epochs; bids are now stale (11 >= 0+10)
        //        but bidding window is still open until epoch_start+duration=12
        //  11  — new bid triggers sweep then fills freed slot
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");

        // Open the settle window, settle epoch 0 (resets epoch_start to 1),
        // then immediately update epoch_duration to 100 so the next bidding
        // window stays open long enough to cover the 10-epoch expiry advance.
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_auction_params(
                &mut vault, &cap, 1_000_000, 3, 100, ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };

        // Advance 10 more Sui epochs so the epoch-0 bids cross the expiry line
        // (ctx.epoch() will be 11; bid_epoch=0; 11 >= 0+10 ✓)
        // The bidding window is epoch_start=1, duration=100 → open until 101
        advance_epochs(&mut scenario, RANDO, 10);

        // New floor bid — sweep fires inside bid(), freeing the 3 stale slots
        do_bid(&mut scenario, SELLER, 1_000_000, b"pid4", b"hash4");

        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            // Two swept slots still empty, one held by SELLER
            assert_eq(attention_market::slots_available(&vault), 2);
            assert_eq(attention_market::vault_balance(&vault),   1_000_000);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_expired_bids_not_swept_before_threshold() {
        // At exactly 9 Sui epochs bids are NOT yet expired (need >= 10).
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");

        advance_epochs(&mut scenario, RANDO, 9);

        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::refund_expired_bids(&mut vault, ts::ctx(&mut scenario));
            // Not expired yet — slot still occupied
            assert_eq(attention_market::slots_available(&vault), 2);
            assert_eq(attention_market::vault_balance(&vault),   2_000_000);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5. settle_epoch
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_settle_epoch_increments_epoch_and_resets_slots() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        // Advance past epoch_duration=1 to open the settle window
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),   1);
            assert_eq(attention_market::slots_available(&vault), 3);
            assert_eq(attention_market::total_earned(&vault),    5_000_000);
            // settle_epoch drained balance to owner
            assert_eq(attention_market::vault_balance(&vault),   0);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_settle_epoch_pays_seller_directly() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            // SELLER received a coin directly from settle_epoch
            assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(SELLER), 0);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_settle_epoch_mints_receipts_to_winners() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, BIDDER1);
        { assert!(ts::has_most_recent_for_address<AttentionReceipt>(BIDDER1), 0); };
        ts::next_tx(&mut scenario, BIDDER2);
        { assert!(ts::has_most_recent_for_address<AttentionReceipt>(BIDDER2), 0); };
        ts::end(scenario);
    }

    #[test]
    fun test_settle_epoch_empty_vault() {
        let mut scenario = setup_vault();
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),   1);
            assert_eq(attention_market::total_earned(&vault),    0);
            assert_eq(attention_market::slots_available(&vault), 3);
            assert_eq(attention_market::vault_balance(&vault),   0);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EEpochNotOver)]
    fun test_settle_epoch_before_window_closes_fails() {
        // epoch_duration=1, epoch_start=0; at Sui epoch 0 the window is open.
        let mut scenario = setup_vault();
        // No advance — settle must fail
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_settle_epoch_non_owner_fails() {
        let mut scenario = setup_vault();
        advance_epochs(&mut scenario, RANDO, 1);
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EVaultClosed)]
    fun test_settle_epoch_on_inactive_vault_fails() {
        let mut scenario = setup_vault();
        advance_epochs(&mut scenario, SELLER, 1);
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::deactivate_for_testing(&mut vault);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6. withdraw
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = attention_market::EZeroBalance)]
    fun test_withdraw_after_settle_is_zero() {
        // settle_epoch drains balance; subsequent withdraw must abort.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_residual_balance() {
        // Residual balance (e.g. active bid not yet settled) can be withdrawn.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            assert_eq(attention_market::vault_balance(&vault), 0);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(SELLER), 0); };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EZeroBalance)]
    fun test_withdraw_zero_balance_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_withdraw_non_owner_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7. close_vault
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_close_vault_empty_vault() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_refunds_active_bidders() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0); };
        ts::next_tx(&mut scenario, BIDDER2);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER2), 0); };
        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_after_settle_has_no_residual() {
        // settle_epoch drains balance to owner; close_vault finds nothing left
        // and should still succeed cleanly.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_close_vault_with_closed_threads_fails() {
        // closed_threads non-empty → table::destroy_empty aborts.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_conversation(
                &mut vault, &cap, b"pid1", ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_close_vault_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EVaultClosed)]
    fun test_bid_on_inactive_vault_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::deactivate_for_testing(&mut vault);
            ts::return_shared(vault);
        };
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8. close_conversation
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_close_conversation_marks_thread_closed() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_conversation(
                &mut vault, &cap, b"pid1", ts::ctx(&mut scenario),
            );
            assert!(attention_market::is_thread_closed(&vault, &b"pid1"),   0);
            assert!(!attention_market::is_thread_closed(&vault, &b"other"), 0);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EAlreadyClosed)]
    fun test_close_conversation_twice_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_conversation(&mut vault, &cap, b"pid1", ts::ctx(&mut scenario));
            attention_market::close_conversation(&mut vault, &cap, b"pid1", ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_close_conversation_non_owner_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_conversation(&mut vault, &cap, b"pid1", ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9. update_encrypted_email
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_update_encrypted_email_replaces_blobs() {
        let mut scenario = setup_vault();
        let new_epk = vector[
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255
        ];
        let new_iv  = vector[255,255,255,255,255,255,255,255,255,255,255,255];
        let new_ct  = vector[
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255
        ];
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_encrypted_email(
                &mut vault, &cap, new_epk, new_iv, new_ct, ts::ctx(&mut scenario),
            );
            let (epk, iv, ct) = attention_market::encrypted_email(&vault);
            assert_eq(*vector::borrow(&epk, 0), 255u8);
            assert_eq(*vector::borrow(&iv,  0), 255u8);
            assert_eq(*vector::borrow(&ct,  0), 255u8);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_update_encrypted_email_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_encrypted_email(
                &mut vault, &cap,
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 10. update_profile
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_update_profile() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault    = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::update_profile(
                &mut registry, &mut vault, &cap,
                string::utf8(b"Alice v2"), string::utf8(b"New bio"),
                2, string::utf8(b"@alice2"), string::utf8(b"alice2@gw"),
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            assert_eq(*attention_market::gateway_email(&vault), string::utf8(b"alice2@gw"));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_update_profile_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault    = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::update_profile(
                &mut registry, &mut vault, &cap,
                string::utf8(b"Hacker"), string::utf8(b""),
                0, string::utf8(b""), string::utf8(b""),
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 11. update_auction_params
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_update_auction_params() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_auction_params(
                &mut vault, &cap, 5_000_000, 5, 200, ts::ctx(&mut scenario),
            );
            assert_eq(attention_market::floor_bid(&vault), 5_000_000);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EBelowGlobalFloor)]
    fun test_update_auction_params_floor_too_low_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_auction_params(&mut vault, &cap, 1, 3, 1, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ETooManySlots)]
    fun test_update_auction_params_too_many_slots_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_auction_params(&mut vault, &cap, 1_000_000, 101, 1, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_update_auction_params_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_auction_params(&mut vault, &cap, 1_000_000, 3, 1, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 12. Multi-epoch lifecycle
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_full_lifecycle_two_epochs() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");

        // Settle epoch 0 — funds go straight to SELLER
        advance_epochs(&mut scenario, SELLER, 1);
        do_settle(&mut scenario);

        // Bid in epoch 1 — window is freshly open
        do_bid(&mut scenario, BIDDER1, 4_000_000, b"pid3", b"hash3");

        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),  1);
            assert_eq(attention_market::total_earned(&vault),   5_000_000);
            // Only the epoch-1 bid is in the balance (epoch 0 was paid out)
            assert_eq(attention_market::vault_balance(&vault),  4_000_000);
            assert_eq(attention_market::total_bids(&vault),     3);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 13. Read-only accessors (smoke test)
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_read_only_accessors() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault    = ts::take_shared<AttentionVault>(&scenario);
            let registry = ts::take_shared<Registry>(&scenario);

            assert_eq(attention_market::floor_bid(&vault),                          1_000_000);
            assert_eq(attention_market::current_epoch(&vault),                      0);
            assert_eq(attention_market::total_earned(&vault),                       0);
            assert_eq(attention_market::total_bids(&vault),                         0);
            assert_eq(attention_market::vault_balance(&vault),                      0);
            assert_eq(attention_market::vault_owner(&vault),                        SELLER);
            assert_eq(*attention_market::gateway_email(&vault),                     string::utf8(b"alice@gateway.example"));
            assert_eq(attention_market::slots_available(&vault),                    3);
            assert_eq(attention_market::current_lowest_bid(&vault),                 1_000_000);
            assert!(attention_market::is_vault_active(&vault),                      0);
            assert!(!attention_market::is_thread_closed(&vault, &b"any"),           0);
            assert_eq(attention_market::registry_count(&registry),                  1);
            assert_eq(attention_market::registry_total_bids(&registry),             0);
            assert_eq(vector::length(attention_market::registry_vaults(&registry)), 1);

            let (epk, iv, ct) = attention_market::encrypted_email(&vault);
            assert_eq(vector::length(&epk), 65);
            assert_eq(vector::length(&iv),  12);
            assert_eq(vector::length(&ct),  32);

            ts::return_shared(vault);
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 14. Gateway email uniqueness
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_registry_email_taken_after_register() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let registry = ts::take_shared<Registry>(&scenario);
            assert!(
                attention_market::registry_email_taken(
                    &registry, string::utf8(b"alice@gateway.example"),
                ),
                0,
            );
            assert!(
                !attention_market::registry_email_taken(
                    &registry, string::utf8(b"bob@gateway.example"),
                ),
                0,
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EDuplicateGatewayEmail)]
    fun test_register_duplicate_gateway_email_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Bob"), string::utf8(b"Bio"),
                1, string::utf8(b"@bob"),
                string::utf8(b"alice@gateway.example"), // duplicate
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                3, 1, 1_000_000,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_profile_to_new_email_releases_old_handle() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault    = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::update_profile(
                &mut registry, &mut vault, &cap,
                string::utf8(b"Alice"), string::utf8(b"Bio"),
                1, string::utf8(b"@alice"),
                string::utf8(b"alice-new@gateway.example"),
                ts::ctx(&mut scenario),
            );
            assert!(
                !attention_market::registry_email_taken(
                    &registry, string::utf8(b"alice@gateway.example"),
                ),
                0,
            );
            assert!(
                attention_market::registry_email_taken(
                    &registry, string::utf8(b"alice-new@gateway.example"),
                ),
                0,
            );
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_profile_same_email_is_allowed() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault    = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::update_profile(
                &mut registry, &mut vault, &cap,
                string::utf8(b"Alice v2"), string::utf8(b"New bio"),
                1, string::utf8(b"@alice"),
                string::utf8(b"alice@gateway.example"), // same — must succeed
                ts::ctx(&mut scenario),
            );
            assert_eq(*attention_market::gateway_email(&vault), string::utf8(b"alice@gateway.example"));
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EDuplicateGatewayEmail)]
    fun test_update_profile_to_taken_email_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Bob"), string::utf8(b"Bio"),
                1, string::utf8(b"@bob"),
                string::utf8(b"bob@gateway.example"),
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                3, 1, 1_000_000,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let cap          = ts::take_from_address<VaultCap>(&scenario, BIDDER1);
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut vault    = ts::take_shared<AttentionVault>(&scenario);
            attention_market::update_profile(
                &mut registry, &mut vault, &cap,
                string::utf8(b"Bob"), string::utf8(b"Bio"),
                1, string::utf8(b"@bob"),
                string::utf8(b"alice@gateway.example"), // taken by SELLER
                ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_shared(registry);
            ts::return_to_address(BIDDER1, cap);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_releases_email_handle() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            assert!(
                !attention_market::registry_email_taken(
                    &registry, string::utf8(b"alice@gateway.example"),
                ),
                0,
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_email_handle_reusable_after_close() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault        = ts::take_shared<AttentionVault>(&scenario);
            let cap          = ts::take_from_address<VaultCap>(&scenario, SELLER);
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::close_vault(&mut registry, vault, cap, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            attention_market::register(
                &mut registry,
                string::utf8(b"Alice2"), string::utf8(b"Bio"),
                1, string::utf8(b"@alice2"),
                string::utf8(b"alice@gateway.example"), // now free
                dummy_ephemeral_pubkey(), dummy_iv(), dummy_ciphertext(),
                3, 1, 1_000_000,
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let registry = ts::take_shared<Registry>(&scenario);
            assert!(
                attention_market::registry_email_taken(
                    &registry, string::utf8(b"alice@gateway.example"),
                ),
                0,
            );
            ts::return_shared(registry);
        };
        ts::end(scenario);
    }
}
