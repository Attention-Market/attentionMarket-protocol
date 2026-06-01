#!/usr/bin/env bash
# deploy.sh — publish AttentionMarket Move contract to Sui testnet
set -e

echo "╔══════════════════════════════════════╗"
echo "║    AttentionMarket — Deploy to Testnet    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Check dependencies
command -v sui >/dev/null 2>&1 || { echo "Error: sui CLI not found."; exit 1; }

# Switch to testnet
echo "[1/2] Switching to testnet..."
sui client switch --env testnet 2>/dev/null || {
  echo "Adding testnet environment..."
  sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
  sui client switch --env testnet
}

# Check balance visually
echo "[2/2] Wallet Balance Status..."
ADDR=$(sui client active-address)
echo "      Active address: $ADDR"
echo ""
sui client balance
echo ""
read -p "Press [ENTER] to build and publish contract..."

# Build and publish
echo ""
echo "Publishing Move contract..."
cd "$(dirname "$0")/move"

# Run publish with standard text output visible to you
sui client publish --gas-budget 100000000

echo ""
echo "▲ PAUSE & COPIES:"
echo "1. Scroll up to 'Published Objects' and look for 'Package ID'."
echo "2. Scroll up to 'Created Objects' and find the ID for '...::attention_market::Registry'."
echo ""
read -p "Enter the Package ID: " PACKAGE_ID
read -p "Enter the Shared Registry Object ID: " REGISTRY_ID

if [ -z "$PACKAGE_ID" ] || [ -z "$REGISTRY_ID" ]; then
  echo "Error: IDs cannot be empty."
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   Deployment complete!                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

cd ..

# Write .env files automatically using your manual inputs
if [ -f "gateway/.env" ]; then
  sed -i.bak \
    -e "s|ATTENTIONMARKET_PACKAGE_ID=.*|ATTENTIONMARKET_PACKAGE_ID=$PACKAGE_ID|" \
    -e "s|REGISTRY_ID=.*|REGISTRY_ID=$REGISTRY_ID|" \
    gateway/.env
  echo "  ✓ Updated gateway/.env"
fi

if [ -f "frontend/.env" ]; then
  sed -i.bak \
    -e "s|VITE_PACKAGE_ID=.*|VITE_PACKAGE_ID=$PACKAGE_ID|" \
    -e "s|VITE_REGISTRY_ID=.*|VITE_REGISTRY_ID=$REGISTRY_ID|" \
    frontend/.env
  echo "  ✓ Updated frontend/.env"
fi

echo ""
echo "Next steps:"
echo "  1. Your frontend is ready to trigger 'register' via Sui Wallet!"
echo "  2. cd gateway && npm install && npm start"
echo "  3. cd frontend && npm install && npm run dev"
echo ""