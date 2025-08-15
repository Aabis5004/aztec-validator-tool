#!/bin/bash
set -e

ADDRESS_FILE="$HOME/.aztec_validator_address"
API_BASE="https://dashtec.xyz/api"

# Get stored address or prompt
if [[ -f "$ADDRESS_FILE" ]]; then
    ADDRESS=$(cat "$ADDRESS_FILE")
else
    read -p "Enter your validator address: " ADDRESS
    echo "$ADDRESS" > "$ADDRESS_FILE"
fi

echo "🔍 Fetching latest epoch info..."
LATEST_EPOCH=$(curl -s "$API_BASE/stats/general" | jq -r '.latestEpoch')
START_EPOCH=$((LATEST_EPOCH - 100))  # last 100 epochs
END_EPOCH=$LATEST_EPOCH

echo "📡 Fetching validator stats for $ADDRESS..."
STATS=$(curl -s "$API_BASE/dashboard/top-validators?startEpoch=$START_EPOCH&endEpoch=$END_EPOCH")
VALIDATOR=$(echo "$STATS" | jq --arg addr "$ADDRESS" '.[] | select(.validatorAddress == $addr)')

if [[ -z "$VALIDATOR" ]]; then
    echo "❌ Validator not found in the top list."
    exit 1
fi

# Basic info
echo ""
echo "══════════════════════════════════════════════════"
echo " Validator Address: $ADDRESS"
echo " Active Status: $(curl -s "$API_BASE/stats/general" | jq -r '.activeValidators') active validators total"
echo " Latest Epoch: $LATEST_EPOCH"
echo "══════════════════════════════════════════════════"

# Rewards and attestations
echo "✅ Total Rewards: $(echo "$VALIDATOR" | jq -r '.totalRewards')"
echo "📝 Total Attestations: $(echo "$VALIDATOR" | jq -r '.totalAttestations')"

# Slashing & accusations
echo "⚠ Checking for slashing events..."
SLASHING=$(curl -s "$API_BASE/validators/slashing-history/$ADDRESS" | jq -r '.[]? // "None"')
if [[ "$SLASHING" == "None" ]]; then
    echo " No slashing history ✅"
else
    echo " Slashing history:"
    echo "$SLASHING"
fi

echo "⚠ Checking for accusations..."
ACCUSATIONS=$(curl -s "$API_BASE/validators/accusations/$ADDRESS" | jq -r '.[]? // "None"')
if [[ "$ACCUSATIONS" == "None" ]]; then
    echo " No accusations ✅"
else
    echo " Accusations:"
    echo "$ACCUSATIONS"
fi

echo "══════════════════════════════════════════════════"
echo "✅ Stats fetched successfully!"
