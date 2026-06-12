# AttentionMarket

> **Bid for attention. Pay only if you win. Prove delivery on-chain.**

AttentionMarket is a decentralised attention auction marketplace built on **Sui**. It lets anyone bid SUI for a guaranteed slot in a seller's inbox — without the seller ever exposing their real email address on-chain.

---

## How It Works

### 1. Sellers register a vault

A seller (creator, expert, professional) deploys an **AttentionVault** by calling `register()`. They set:

- A **public gateway email** — the MX address bidders see and that the email forwarder listens on.
- Their **real inbox** — stored on-chain as an ECDH / AES-GCM encrypted blob. Only the gateway's private key can decrypt it.
- A **floor bid** (minimum 0.001 SUI), **slots per epoch** (up to 100), and **epoch duration**.

The vault becomes a shared Sui object. The seller receives a `VaultCap` capability object that gates all privileged actions.

---

### 2. Bidders compete for slots

Anyone can call `bid()` during the open bidding window. Under the hood:

1. **Expired bids are swept first** — any bid placed 10+ epochs ago is refunded on the spot.
2. **If a slot is open** — the bid fills it immediately.
3. **If all slots are full** — the bid must beat the current lowest bid. The displaced bidder is refunded **immediately** via an on-chain transfer. No claim step needed.

Each bid records:

| Field | What it stores |
|---|---|
| `sender_email_hash` | `sha256(bidder_email)` — email is never stored in plaintext |
| `payment_id` | `sha256(emailHash + ":" + vaultId)` — used to route delivery |
| `bid_epoch` | The vault epoch in which the bid was placed |

A `BidPlaced` event is emitted and indexed by the frontend.

---

### 3. Seller settles the epoch

Once the epoch window closes, the seller calls `settle_epoch()`. This:

- Mints a **soulbound `AttentionReceipt`** to every winning slot holder.
- Resets all slots and increments the epoch counter.
- Deducts the platform fee (up to 10%, set in basis points on the `Registry`), then transfers the net proceeds directly to the vault owner.

The `AttentionReceipt` is non-transferable (`key` only, no `store`). It contains the `payment_id`, `gateway_email`, seller name, and the amount paid.

---

### 4. Winners get through

A winner uses their `AttentionReceipt` to **sign a delivery token** on the frontend at any time. The frontend generates a signed JWT / bearer token embedding the `payment_id`.

The **email forwarder gateway** sits in front of the seller's real inbox:

1. An incoming email arrives at `gateway_email`.
2. The gateway checks the sender's `payment_id` against on-chain state — verifying the receipt is valid and the thread hasn't been closed.
3. If valid, the gateway decrypts the seller's real inbox address using the ECDH private key and forwards the email.
4. If the `payment_id` has been closed via `close_conversation()`, the gateway permanently rejects it.

---

## Privacy Model

| Data | Where it lives | Who can read it |
|---|---|---|
| Seller's real inbox | On-chain, ECDH-encrypted | Gateway only (holds private key) |
| `gateway_email` | On-chain, plaintext | Everyone — it's public |
| Bidder's email | Off-chain | Bidder only |
| `sender_email_hash` | On-chain as `sha256(email)` | Anyone, but not reversible |
| `payment_id` | On-chain as `sha256(emailHash + ":" + vaultId)` | Anyone, but not reversible |

---

## Fee Model

- Platform fees are configured on the `Registry` by the deployer (`PlatformCap` holder).
- Fee is expressed in **basis points** (max 1000 = 10%). Default is 0.
- Fees are deducted at `settle_epoch()` and `withdraw()` and sent to the `fee_recipient` address.

---

## Seller Controls

| Action | Function | Effect |
|---|---|---|
| Settle an epoch | `settle_epoch()` | Mints receipts, pays seller, resets slots |
| Close a conversation | `close_conversation()` | Permanently invalidates a `payment_id` at the gateway |
| Withdraw residual balance | `withdraw()` | Pulls any remaining SUI after expired-bid sweeps |
| Update profile | `update_profile()` | Name, bio, category, social handle, gateway email |
| Update auction params | `update_auction_params()` | Floor bid, slots, epoch duration |
| Rotate encrypted inbox | `update_encrypted_email()` | Re-encrypts to a new ephemeral keypair |
| Close vault | `close_vault()` | Refunds all active bidders, deletes vault and cap |

---

## Expiry & Refunds

Bids that remain unsettled for **10 or more epochs** beyond their auction epoch can be refunded by anyone calling `refund_expired_bids()`. This protects bidders if a seller goes dark.

---

## Contract Overview

```
attentionmarket::attention_market
├── Registry            — shared global object; vault index + fee config
├── AttentionVault      — shared per-seller object; holds bids + encrypted inbox
├── VaultCap            — owned by seller; required for privileged actions
├── AttentionReceipt    — soulbound; minted to winners at settle_epoch()
└── PlatformCap         — owned by deployer; controls fee settings
```

### Key constants

| Constant | Value | Meaning |
|---|---|---|
| `GLOBAL_FLOOR` | 1,000,000 MIST | Minimum bid (0.001 SUI) |
| `MAX_SLOTS` | 100 | Max slots per epoch |
| `REFUND_AFTER_EPOCHS` | 10 | Epochs before a bid can be expired-refunded |
| `MAX_FEE_BPS` | 1,000 | Platform fee cap (10%) |

---

## System Architecture

```
┌─────────────┐     bid tx          ┌──────────────────┐
│   Bidder    │ ──────────────────► │   Sui Network    │
│  (browser)  │                     │  AttentionVault  │
└──────┬──────┘                     └────────┬─────────┘
       │ email verify                        │ settle_epoch()
       ▼                                     ▼
┌─────────────────┐              ┌──────────────────────┐
│  Verification   │              │   AttentionReceipt   │
│    Service      │              │   (soulbound NFT)    │
└─────────────────┘              └──────────┬───────────┘
                                            │ sign delivery token
                                            ▼
┌─────────────┐   signed token   ┌──────────────────────┐
│   Winner    │ ───────────────► │  Gateway / Forwarder │
│  (browser)  │                  │  (checks payment_id, │
└─────────────┘                  │  decrypts real inbox,│
                                 │  forwards email)     │
                                 └──────────────────────┘
```

---

## License

MIT
