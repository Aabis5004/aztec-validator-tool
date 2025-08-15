#!/bin/bash
set -e

# ====== COLORS ======
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

# ====== CONFIG ======
BASE_URL="https://api.mainnet.aztec.network"
COOKIE_FILE="$HOME/.aztec_cookie"

# ====== HELP ======
show_help() {
    echo -e "${CYAN}${BOLD}Aztec Validator Stats Tool${NC}"
    echo -e "${CYAN}by Aabis Lone${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  aztec-stats <validator_address>"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  --set-cookie         Set Cloudflare cookie"
    echo -e "  --help, -h           Show this help message"
}

# ====== VALIDATE ADDRESS ======
validate_address() {
    if [[ ! $1 =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -e "${RED}❌ Invalid Ethereum address${NC}"
        exit 1
    fi
}

# ====== DEPENDENCIES ======
check_dependencies() {
    for dep in jq curl; do
        if ! command -v $dep >/dev/null; then
            echo -e "${RED}❌ Missing $dep. Install it first.${NC}"
            exit 1
        fi
    done
}

# ====== API CALL ======
make_api_call() {
    local url=$1
    local response http_code
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" $COOKIE_HEADER "$url")
    http_code=$(echo "$response" | sed -n 's/.*HTTPSTATUS://p')
    response=$(echo "$response" | sed 's/HTTPSTATUS:.*//')

    if [ "$http_code" -eq 200 ]; then
        echo "$response"
    elif [ "$http_code" -eq 403 ]; then
        echo -e "${RED}❌ Cloudflare blocked request. Run --set-cookie${NC}"
        exit 1
    elif [ "$http_code" -eq 404 ]; then
        echo -e "${YELLOW}⚠️ No data found${NC}"
    else
        echo -e "${RED}❌ API request failed ($http_code)${NC}"
    fi
}

# ====== ARGUMENTS ======
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

ADDRESS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --set-cookie)
            echo -n "Enter Cloudflare cookie: "
            read -r COOKIE
            echo "$COOKIE" > "$COOKIE_FILE"
            echo -e "${GREEN}✅ Cookie saved${NC}"
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        0x*)
            ADDRESS=$1
            shift
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

validate_address "$ADDRESS"
check_dependencies

# ====== LOAD COOKIE ======
COOKIE_HEADER=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE_HEADER="-H Cookie:$(cat "$COOKIE_FILE")"
    echo -e "${GREEN}🍪 Using saved cookie${NC}"
fi

# ====== FETCH AND DISPLAY ======
echo -e "${BOLD}${CYAN}🔍 Validator Stats for: ${YELLOW}$ADDRESS${NC}"

# Performance
perf=$(make_api_call "$BASE_URL/validators/$ADDRESS/performance")
if [[ -n "$perf" ]]; then
    total_att=$(echo "$perf" | jq -r '.totalAttestations // "N/A"')
    missed_att=$(echo "$perf" | jq -r '.missedAttestations // "N/A"')
    total_prop=$(echo "$perf" | jq -r '.totalProposals // "N/A"')
    missed_prop=$(echo "$perf" | jq -r '.missedProposals // "N/A"')
    success=$(echo "$perf" | jq -r '.successRate // "N/A"')
    
    echo -e "${GREEN}📈 Performance${NC}"
    echo -e "   Attestations: $((total_att - missed_att))/$total_att"
    echo -e "   Proposals: $((total_prop - missed_prop))/$total_prop"
    echo -e "   Success Rate: $success%"
    echo ""
fi

# Slashing
slashing=$(make_api_call "$BASE_URL/validators/$ADDRESS/slashing")
slash_count=$(echo "$slashing" | jq 'length' 2>/dev/null || echo 0)
echo -e "${RED}🔨 Slashing Events${NC}"
if [[ "$slash_count" == "0" ]]; then
    echo -e "   ✅ Clean record"
else
    echo "$slashing" | jq -r '.[] | "   Epoch: \(.epoch) | Reason: \(.reason) | Amount: \(.amount)"'
fi
echo ""

# Accusations
acc=$(make_api_call "$BASE_URL/validators/$ADDRESS/accusations")
acc_count=$(echo "$acc" | jq 'length' 2>/dev/null || echo 0)
echo -e "${YELLOW}⚠️ Accusations${NC}"
if [[ "$acc_count" == "0" ]]; then
    echo -e "   ✅ Clean record"
else
    echo "$acc" | jq -r '.[] | "   Epoch: \(.epoch) | Type: \(.type) | Status: \(.status)"'
fi
echo ""

# Committees
comm=$(make_api_call "$BASE_URL/validators/$ADDRESS/committees")
comm_count=$(echo "$comm" | jq 'length' 2>/dev/null || echo 0)
echo -e "${GREEN}👥 Committee Participation${NC}"
if [[ "$comm_count" == "0" ]]; then
    echo -e "   ⚠️ No committee data"
else
    echo "$comm" | jq -r '.[] | "   Epoch: \(.epoch) | Role: \(.role) | Committee: \(.committee)"' | head -10
    if [[ "$comm_count" -gt 10 ]]; then
        echo -e "   ... and $((comm_count - 10)) more assignments"
    fi
fi

echo -e "${BOLD}${GREEN}✅ Done${NC}"
