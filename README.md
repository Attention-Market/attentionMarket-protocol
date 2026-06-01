# Attention Market - SpamShield 🛡️
### Micropayment email filter on Sui

> *Spam is free. SpamShield makes it cost $0.01.*

SpamShield is a programmable email filter that requires a Sui micropayment before any email reaches your inbox. Spammers sending millions of emails face an insurmountable economic wall. Legitimate senders pay once — an invisible cost — and their email arrives instantly.

Built for the **Programmable Money, Payments & Financial Systems on Sui** hackathon track.

---

## How it works

```
Sender → SMTP Gateway → Payment check → Deliver (paid/whitelisted)
                                     ↓
                               Quarantine → Bounce with pay link
                                     ↓
                            Sender pays on Sui
                                     ↓
                         EmailPaid event emitted
                                     ↓
                         Event listener releases email
```

1. **Email arrives** at your SpamShield SMTP gateway
2. **Gateway computes** a deterministic `payment_id = sha256(sender + recipient + emailHash)`
3. **Sui RPC check**: has this payment_id been paid on-chain?
   - **Yes / whitelisted** → deliver immediately
   - **No** → quarantine + send bounce email with a pay link
4. **Sender clicks the link**, connects their Sui wallet, pays ~0.01 SUI
5. **Move contract** records the payment and emits an `EmailPaid` event
6. **Event listener** catches it, releases the email from quarantine, delivers it
7. **Recipient earns** the fee — withdrawable anytime from their vault

---

## Architecture

```
spamshield/
├── move/                   # Sui Move smart contract
│   ├── Move.toml
│   └── sources/
│       └── email_payment.move   # RecipientVault, pay_for_email, events
│
├── gateway/                # Node.js SMTP gateway + API
│   ├── src/
│   │   ├── index.js        # Entry point
│   │   ├── smtp-server.js  # Intercepts incoming SMTP
│   │   ├── sui-client.js   # Sui RPC + event helpers
│   │   ├── quarantine.js   # In-memory email store
│   │   ├── event-listener.js  # Polls for EmailPaid events
│   │   ├── mailer.js       # Sends bounces + delivers released mail
│   │   └── api.js          # REST API for dashboard
│   ├── package.json
│   └── .env.example
│
├── frontend/               # React dashboard + payment page
│   ├── src/
│   │   ├── main.jsx        # Sui wallet providers + router
│   │   ├── Dashboard.jsx   # Recipient's quarantine dashboard
│   │   ├── PayPage.jsx     # Sender's payment flow
│   │   └── index.css       # Design system
│   ├── package.json
│   └── vite.config.js
│
└── deploy.sh               # One-command contract deployment
```

---

## Quick start

### Prerequisites
- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) installed
- Node.js 20+
- A Sui testnet wallet with some SUI ([faucet](https://faucet.sui.io))
- A Gmail account (or any SMTP provider) for outbound mail

### 1. Deploy the Move contract

```bash
chmod +x deploy.sh
./deploy.sh
```

This publishes the contract to testnet, creates your `RecipientVault`, and prints the IDs you'll need.

### 2. Configure the gateway

```bash
cd gateway
cp .env.example .env
# Edit .env with your IDs from deploy.sh output + SMTP credentials
npm install
npm start
```

### 3. Start the frontend

```bash
cd frontend
cp .env.example .env
# Set VITE_PACKAGE_ID from deploy output
npm install
npm run dev
```

### 4. Test it

```bash
# Send a test email to the gateway (it listens on port 2525)
curl --url 'smtp://localhost:2525' \
  --mail-from 'spammer@example.com' \
  --mail-rcpt 'you@yoursite.com' \
  --upload-file - << 'EOF'
From: spammer@example.com
To: you@yoursite.com
Subject: Buy my crypto course

You definitely want this.
EOF
```

You'll get a bounce email with a pay link. Open it, connect Sui wallet, pay, and watch the email release.

---

## Move contract

### Key objects

**`RecipientVault`** (shared object, one per protected inbox)
```move
public struct RecipientVault has key {
    id: UID,
    owner: address,
    payments: Table<vector<u8>, u64>,  // payment_id → amount
    whitelist: Table<String, bool>,     // sender_email → allowed
    balance: u64,                       // earned MIST
    min_payment: u64,                   // configurable threshold
}
```

**`VaultCap`** (owned by recipient, required for admin actions)

### Key functions

| Function | Caller | Description |
|---|---|---|
| `create_vault()` | Recipient | Deploy once, get VaultCap |
| `pay_for_email(vault, payment_id, sender_email, coin)` | Sender | Pay to release email |
| `add_to_whitelist(vault, cap, email)` | Recipient | Bypass payment for trusted senders |
| `withdraw(vault, cap)` | Recipient | Claim earned SUI |
| `set_min_payment(vault, cap, amount)` | Recipient | Change fee threshold |

### Events

| Event | When | Contains |
|---|---|---|
| `EmailPaid` | Payment recorded | `payment_id`, `sender_email`, `recipient`, `amount` |
| `FundsWithdrawn` | Recipient withdraws | `recipient`, `amount` |
| `WhitelistUpdated` | Whitelist changes | `sender_email`, `added` |

---

## Why Sui makes this possible

| Sui feature | How SpamShield uses it |
|---|---|
| **Shared objects** | RecipientVault accessible by any sender globally |
| **PTBs** | Sender can `split coin + pay_for_email` atomically |
| **Sub-cent fees** | ~$0.001 gas makes micropayments economical |
| **On-chain events** | Gateway reacts to payments without polling state |
| **Strong ownership** | VaultCap enforces that only recipient can withdraw |
| **Type safety** | Move prevents double-payments via Table key uniqueness |

---

## Economic model

- **Spam economics**: 1M emails/day × $0.01 = $10,000/day cost for spammers → impossible
- **Legitimate sender**: one email = $0.01 = invisible
- **Recipient earns**: every email that passes through earns them SUI
- **Whitelist**: zero friction for known contacts

---

## Hackathon track alignment

**Trust-Minimized Finance** — enforcement is fully on-chain. The recipient never needs to trust the gateway; the Move contract is the source of truth.

**Payments & Consumer Finance** — real-world product with a clear UX story and measurable economic impact.

**Novel PTB usage** — `split_coin → pay_for_email` in one atomic transaction.

---

## Production roadmap

- [ ] Store `Coin<SUI>` inside the vault object for real withdrawals
- [ ] MX record integration (proper email routing)
- [ ] TLS/STARTTLS support in SMTP gateway
- [ ] Persistent quarantine store (Redis/SQLite)
- [ ] On-chain whitelist sync (poll `WhitelistUpdated` events)
- [ ] Multi-recipient support (one vault per domain)
- [ ] zkLogin integration (senders pay without a pre-existing wallet)
- [ ] Retroactive payment streaming (earned fees auto-invested in yield vault)

---

## License

MIT
