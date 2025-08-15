#!/bin/bash
set -e

# Colors for highlights
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ADDRESS_FILE="$HOME/.aztec_validator_address"
API_BASE="https://dashtec.xyz/api"

# Get stored address or prompt
if [[ -f "$ADDRESS_FILE" ]]; then
    ADDRESS=$(cat "$ADDRESS_FILE")
else
    read -p "Enter your validator address: " ADDRESS
    echo "$ADDRESS" > "$ADDRESS_FILE"
fi

echo -e "${CYAN}🔍 Fetching latest epoch info...${NC}"
LATEST_EPOCH=$(curl -s "$API_BASE/stats/general" | jq -r '.latestEpoch')
START_EPOCH=$((LATEST_EPOCH - 100))  # last 100 epochs
END_EPOCH=$LATEST_EPOCH

GENERAL=$(curl -s "$API_BASE/stats/general")

ACTIVE_VALIDATORS=$(echo "$GENERAL" | jq -r '.activeValidators')
TOTAL_VALIDATORS=$(echo "$GENERAL" | jq -r '.totalValidators')

echo -e "\n${CYAN}📡 Fetching validator stats for $ADDRESS...${NC}"
STATS=$(curl -s "$API_BASE/dashboard/top-validators?startEpoch=$START_EPOCH&endEpoch=$END_EPOCH")
VALIDATOR=$(echo "$STATS" | jq --arg addr "$ADDRESS" '.[] | select(.validatorAddress == $addr)')

if [[ -z "$VALIDATOR" ]]; then
    echo -e "${RED}❌ Validator not found in the top list.${NC}"
    exit 1
fi

# Basic info
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e " Validator Address: ${YELLOW}$ADDRESS${NC}"
echo -e " Active Validators: ${GREEN}$ACTIVE_VALIDATORS${NC} / $TOTAL_VALIDATORS"
echo -e " Latest Epoch: ${YELLOW}$LATEST_EPOCH${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# Rewards and attestations
REWARDS=$(echo "$VALIDATOR" | jq -r '.totalRewards')
ATTESTATIONS=$(echo "$VALIDATOR" | jq -r '.totalAttestations')
COMMITTEE_PARTICIPATION=$(echo "$VALIDATOR" | jq -r '.committeeParticipationRate')

echo -e "✅ Total Rewards: ${GREEN}$REWARDS${NC}"
echo -e "📝 Total Attestations: ${GREEN}$ATTESTATIONS${NC}"
echo -e "📊 Committee Participation: ${YELLOW}$COMMITTEE_PARTICIPATION%${NC}"

# Slashing & accusations
echo -e "\n${CYAN}⚠ Checking for slashing events...${NC}"
SLASHING=$(curl -s "$API_BASE/validators/slashing-history/$ADDRESS")
if [[ "$SLASHING" == "[]" || -z "$SLASHING" ]]; then
    echo -e " No slashing history ${GREEN}✅${NC}"
else
    echo -e "${RED} Slashing history detected:${NC}"
    echo "$SLASHING" | jq -r '.[] | "- Epoch: \(.epoch), Reason: \(.reason)"'
fi

echo -e "\n${CYAN}⚠ Checking for accusations...${NC}"
ACCUSATIONS=$(curl -s "$API_BASE/validators/accusations/$ADDRESS")
if [[ "$ACCUSATIONS" == "[]" || -z "$ACCUSATIONS" ]]; then
    echo -e " No accusations ${GREEN}✅${NC}"
else
    echo -e "${RED} Accusations detected:${NC}"
    echo "$ACCUSATIONS" | jq -r '.[] | "- Epoch: \(.epoch), Accuser: \(.accuser)"'
fi

echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
echo -e " ${GREEN}✅ Stats fetched successfully!${NC}"
