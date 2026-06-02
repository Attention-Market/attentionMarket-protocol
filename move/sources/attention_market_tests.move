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
                100,       // epoch_duration
                1_000_000, // floor_bid = GLOBAL_FLOOR
                ts::ctx(&mut scenario),
            );
            ts::return_shared(registry);
        };
        scenario
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
                3, 100, 999_999,
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
                0, 100, 1_000_000,
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
                101, 100, 1_000_000,
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
            assert_eq(attention_market::slots_available(&vault),            2);
            assert_eq(attention_market::vault_balance(&vault),              1_000_000);
            assert_eq(attention_market::total_bids(&vault),                 1);
            assert_eq(attention_market::registry_total_bids(&registry),     1);
            ts::return_shared(vault);
            ts::return_shared(registry);
            assert!(ts::has_most_recent_for_address<AttentionReceipt>(BIDDER1), 0);
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
    fun test_bid_outbids_lowest_slot() {
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

    // ══════════════════════════════════════════════════════════════════════════
    // 4. claim_refund
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_claim_refund_after_outbid() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        do_bid(&mut scenario, SELLER,  5_000_000, b"pid4", b"hash4");
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::claim_refund(&mut vault, 0, ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        {
            assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_claim_refund_wrong_address_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        do_bid(&mut scenario, SELLER,  5_000_000, b"pid4", b"hash4");
        ts::next_tx(&mut scenario, BIDDER2);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::claim_refund(&mut vault, 0, ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_claim_refund_double_claim_fails() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        do_bid(&mut scenario, SELLER,  5_000_000, b"pid4", b"hash4");
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::claim_refund(&mut vault, 0, ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };
        ts::next_tx(&mut scenario, BIDDER1);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            attention_market::claim_refund(&mut vault, 0, ts::ctx(&mut scenario));
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
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),   1);
            assert_eq(attention_market::slots_available(&vault), 3);
            assert_eq(attention_market::total_earned(&vault),    5_000_000);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_settle_epoch_empty_vault() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),   1);
            assert_eq(attention_market::total_earned(&vault),    0);
            assert_eq(attention_market::slots_available(&vault), 3);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_settle_epoch_non_owner_fails() {
        let mut scenario = setup_vault();
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

    // ══════════════════════════════════════════════════════════════════════════
    // 6. withdraw
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_withdraw_after_settle() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::vault_balance(&vault), 0);
            ts::return_shared(vault);
            assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(SELLER), 0);
        };
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
        // Simplest case: no bids, no whitelist, no closed threads.
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
            // vault and cap are consumed — no return needed
        };
        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_refunds_active_bidders() {
        // Two bidders win slots; vault is closed without settling.
        // Both should receive their money back automatically.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");

        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
        };

        // Both bidders should have received refund coins
        ts::next_tx(&mut scenario, BIDDER1);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0); };

        ts::next_tx(&mut scenario, BIDDER2);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER2), 0); };

        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_refunds_pending_outbid() {
        // Slot 0 has an outbid bidder with unclaimed pending_refund.
        // close_vault should push that refund out automatically.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 2_000_000, b"pid2", b"hash2");
        do_bid(&mut scenario, RANDO,   3_000_000, b"pid3", b"hash3");
        // Outbid BIDDER1 — pending_refund goes into slot 0
        do_bid(&mut scenario, SELLER,  5_000_000, b"pid4", b"hash4");

        // BIDDER1 has NOT claimed their refund yet — close_vault must do it
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, BIDDER1);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(BIDDER1), 0); };

        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_returns_earned_balance_to_seller() {
        // Seller settled an epoch (funds landed in vault.balance) but hasn't
        // withdrawn yet. close_vault should send them home.
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");

        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };

        // vault.balance = 2_000_000 (settled, not withdrawn)
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, SELLER);
        { assert!(ts::has_most_recent_for_address<coin::Coin<SUI>>(SELLER), 0); };

        ts::end(scenario);
    }

    #[test]
    fun test_close_vault_with_whitelist_entries() {
        // whitelist is non-empty — close_vault uses table::drop, so it succeeds.
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::add_to_whitelist(
                &mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            // Should succeed even though whitelist is non-empty
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_close_vault_with_closed_threads_fails() {
        // closed_threads is non-empty → table::destroy_empty aborts.
        // The seller must not have any closed conversation entries to delete cleanly.
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
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            // Aborts because closed_threads is non-empty
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_close_vault_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            let cap   = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::close_vault(vault, cap, ts::ctx(&mut scenario));
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
        // bid() should abort with EVaultClosed
        do_bid(&mut scenario, BIDDER1, 1_000_000, b"pid1", b"hash1");
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EVaultClosed)]
    fun test_settle_epoch_on_inactive_vault_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::deactivate_for_testing(&mut vault);
            // settle_epoch() should abort with EVaultClosed
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
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
            assert!(attention_market::is_thread_closed(&vault, &b"pid1"),  0);
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
    // 10. whitelist
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_whitelist_add_and_check() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::add_to_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            assert!(attention_market::is_whitelisted(&vault, &b"hash_alice"), 0);
            assert!(!attention_market::is_whitelisted(&vault, &b"hash_bob"),  0);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_whitelist_remove() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::add_to_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            attention_market::remove_from_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            assert!(!attention_market::is_whitelisted(&vault, &b"hash_alice"), 0);
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::EAlreadyWhitelisted)]
    fun test_whitelist_add_duplicate_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::add_to_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            attention_market::add_to_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotWhitelisted)]
    fun test_whitelist_remove_absent_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::remove_from_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = attention_market::ENotOwner)]
    fun test_whitelist_add_non_owner_fails() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, RANDO);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::add_to_whitelist(&mut vault, &cap, b"hash_alice", ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 11. update_profile
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_update_profile() {
        let mut scenario = setup_vault();
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_profile(
                &mut vault, &cap,
                string::utf8(b"Alice v2"), string::utf8(b"New bio"),
                2, string::utf8(b"@alice2"), string::utf8(b"alice2@gw"),
                ts::ctx(&mut scenario),
            );
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
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::update_profile(
                &mut vault, &cap,
                string::utf8(b"Hacker"), string::utf8(b""),
                0, string::utf8(b""), string::utf8(b""),
                ts::ctx(&mut scenario),
            );
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 12. update_auction_params
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
            attention_market::update_auction_params(&mut vault, &cap, 1, 3, 100, ts::ctx(&mut scenario));
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
            attention_market::update_auction_params(&mut vault, &cap, 1_000_000, 101, 100, ts::ctx(&mut scenario));
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
            attention_market::update_auction_params(&mut vault, &cap, 1_000_000, 3, 100, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 13. Multi-epoch lifecycle
    // ══════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_full_lifecycle_two_epochs() {
        let mut scenario = setup_vault();
        do_bid(&mut scenario, BIDDER1, 2_000_000, b"pid1", b"hash1");
        do_bid(&mut scenario, BIDDER2, 3_000_000, b"pid2", b"hash2");
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::settle_epoch(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        ts::next_tx(&mut scenario, SELLER);
        {
            let mut vault = ts::take_shared<AttentionVault>(&scenario);
            let cap       = ts::take_from_address<VaultCap>(&scenario, SELLER);
            attention_market::withdraw(&mut vault, &cap, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(SELLER, cap);
        };
        do_bid(&mut scenario, BIDDER1, 4_000_000, b"pid3", b"hash3");
        ts::next_tx(&mut scenario, SELLER);
        {
            let vault = ts::take_shared<AttentionVault>(&scenario);
            assert_eq(attention_market::current_epoch(&vault),  1);
            assert_eq(attention_market::total_earned(&vault),   5_000_000);
            assert_eq(attention_market::vault_balance(&vault),  4_000_000);
            assert_eq(attention_market::total_bids(&vault),     3);
            ts::return_shared(vault);
        };
        ts::end(scenario);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 14. Read-only accessors (smoke test)
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
            assert!(!attention_market::is_whitelisted(&vault, &b"any"),             0);
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
}
