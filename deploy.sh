#!/usr/bin/env bash
# deploy.sh — publish SpamShield Move contract to Sui testnet and set up vault
set -e

echo "╔══════════════════════════════════════╗"
echo "║    SpamShield — Deploy to Testnet    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Check dependencies
command -v sui >/dev/null 2>&1 || { echo "Error: sui CLI not found. Install from https://docs.sui.io/guides/developer/getting-started/sui-install"; exit 1; }

# Switch to testnet
echo "[1/4] Switching to testnet..."
sui client switch --env testnet 2>/dev/null || {
  echo "Adding testnet environment..."
  sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
  sui client switch --env testnet
}

# Check balance
echo "[2/4] Checking wallet balance..."
ADDR=$(sui client active-address)
echo "      Active address: $ADDR"
BALANCE=$(sui client balance --json 2>/dev/null | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['totalBalance'] if data else '0')" 2>/dev/null || echo "0")
echo "      Balance: $BALANCE MIST"

if [ "$BALANCE" -lt "200000000" ] 2>/dev/null; then
  echo ""
  echo "  Low balance detected. Requesting testnet SUI from faucet..."
  sui client faucet || {
    echo "  Faucet failed. Get testnet SUI at: https://faucet.sui.io"
    echo "  Then run this script again."
    exit 1
  }
  sleep 3
fi

# Build and publish
echo "[3/4] Building and publishing Move contract..."
cd "$(dirname "$0")/move"

PUBLISH_OUTPUT=$(sui client publish \
  --gas-budget 100000000 \
  --json 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Error: Publication failed. Check your Move code."
  exit 1
fi

# Extract package ID
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for obj in data.get('objectChanges', []):
    if obj.get('type') == 'published':
        print(obj['packageId'])
        break
" 2>/dev/null)

echo "      Package ID: $PACKAGE_ID"

# Create recipient vault
echo "[4/4] Creating recipient vault..."
cd ..

VAULT_OUTPUT=$(sui client call \
  --package "$PACKAGE_ID" \
  --module email_payment \
  --function create_vault \
  --gas-budget 10000000 \
  --json 2>/dev/null)

# Extract vault object ID and cap ID
VAULT_ID=$(echo "$VAULT_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for obj in data.get('objectChanges', []):
    if obj.get('type') == 'created' and 'RecipientVault' in obj.get('objectType', ''):
        print(obj['objectId'])
        break
" 2>/dev/null)

CAP_ID=$(echo "$VAULT_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for obj in data.get('objectChanges', []):
    if obj.get('type') == 'created' and 'VaultCap' in obj.get('objectType', ''):
        print(obj['objectId'])
        break
" 2>/dev/null)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   Deployment complete!                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Package ID  : $PACKAGE_ID"
echo "  Vault ID    : $VAULT_ID"
echo "  VaultCap ID : $CAP_ID"
echo "  Owner       : $ADDR"
echo ""
echo "Copy these into gateway/.env:"
echo ""
echo "  SPAMSHIELD_PACKAGE_ID=$PACKAGE_ID"
echo "  RECIPIENT_VAULT_ID=$VAULT_ID"
echo "  RECIPIENT_ADDRESS=$ADDR"
echo ""
echo "And into frontend/.env:"
echo ""
echo "  VITE_PACKAGE_ID=$PACKAGE_ID"
echo "  VITE_VAULT_ID=$VAULT_ID"
echo ""

# Write .env files automatically if they exist
if [ -f "gateway/.env" ]; then
  sed -i.bak \
    -e "s|SPAMSHIELD_PACKAGE_ID=.*|SPAMSHIELD_PACKAGE_ID=$PACKAGE_ID|" \
    -e "s|RECIPIENT_VAULT_ID=.*|RECIPIENT_VAULT_ID=$VAULT_ID|" \
    -e "s|RECIPIENT_ADDRESS=.*|RECIPIENT_ADDRESS=$ADDR|" \
    gateway/.env
  echo "  ✓ Updated gateway/.env"
fi

if [ -f "frontend/.env" ]; then
  sed -i.bak \
    -e "s|VITE_PACKAGE_ID=.*|VITE_PACKAGE_ID=$PACKAGE_ID|" \
    gateway/.env
  echo "  ✓ Updated frontend/.env"
fi

echo ""
echo "Next steps:"
echo "  1. cd gateway && npm install && npm start"
echo "  2. cd frontend && npm install && npm run dev"
echo "  3. Send a test email to localhost:2525"
echo ""
