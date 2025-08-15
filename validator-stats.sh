#!/bin/bash
set -e

# Colors
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

if [ $# -lt 1 ]; then
    echo "Usage: aztec-stats <validator_address> [--epochs start:end] [--last N] [--set-cookie]"
    exit 1
fi

ADDRESS=$1
shift

# Default API URLs
BASE_URL="https://api.mainnet.aztec.network"
EPOCHS_PARAM=""
COOKIE_FILE="$HOME/.aztec_cookie"

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --epochs)
            EPOCHS_PARAM="&epochs=$2"
            shift 2
            ;;
        --last)
            EPOCHS_PARAM="&last=$2"
            shift 2
            ;;
        --set-cookie)
            echo -n "Enter Cloudflare cookie value: "
            read COOKIE
            echo "$COOKIE" > "$COOKIE_FILE"
            echo "✅ Cookie saved to $COOKIE_FILE"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Load cookie if exists
COOKIE_HEADER=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE_HEADER="-H Cookie:$(cat $COOKIE_FILE)"
fi

echo -e "${BOLD}${CYAN}Fetching validator stats for:$NC $ADDRESS${NC}"

# Validator performance
echo -e "\n${BOLD}📊 Performance Stats:${NC}"
curl -s $COOKIE_HEADER "$BASE_URL/validators/$ADDRESS/performance?${EPOCHS_PARAM}" | jq .

# Accusations
echo -e "\n${BOLD}${YELLOW}⚠ Accusations:${NC}"
curl -s $COOKIE_HEADER "$BASE_URL/validators/$ADDRESS/accusations" | jq .

# Slashing
echo -e "\n${BOLD}${RED}🔨 Slashing Events:${NC}"
curl -s $COOKIE_HEADER "$BASE_URL/validators/$ADDRESS/slashing" | jq .

# Committee participation
echo -e "\n${BOLD}${GREEN}👥 Committee Participation:${NC}"
curl -s $COOKIE_HEADER "$BASE_URL/validators/$ADDRESS/committees" | jq .
