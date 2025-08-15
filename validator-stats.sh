#!/bin/bash
set -e

# Colors for better output
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

# Configuration
BASE_URL="https://api.mainnet.aztec.network"
COOKIE_FILE="$HOME/.aztec_cookie"
EPOCHS_PARAM=""

# Help function
show_help() {
    echo -e "${CYAN}${BOLD}Aztec Validator Stats Tool${NC}"
    echo -e "${CYAN}by Aabis Lone${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  aztec-stats <validator_address> [options]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  --epochs START:END    Get stats for specific epoch range"
    echo -e "  --last N             Get stats for last N epochs"
    echo -e "  --set-cookie         Set Cloudflare cookie (interactive)"
    echo -e "  --help, -h           Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  aztec-stats 0x742d35Cc6634C0532925a3b8D06C0E04F474C"
    echo -e "  aztec-stats 0x742d35Cc6634C0532925a3b8D06C0E04F474C --last 100"
    echo -e "  aztec-stats 0x742d35Cc6634C0532925a3b8D06C0E04F474C --epochs 1800:1900"
}

# Validate Ethereum address
validate_address() {
    local addr=$1
    if [[ ! $addr =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -e "${RED}❌ Invalid Ethereum address format${NC}"
        echo -e "${YELLOW}Address should be 42 characters starting with 0x${NC}"
        exit 1
    fi
}

# Check if required tools are available
check_dependencies() {
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}❌ jq is required but not installed${NC}"
        echo -e "${YELLOW}Install with: sudo apt install jq (Linux) or brew install jq (macOS)${NC}"
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ curl is required but not installed${NC}"
        exit 1
    fi
}

# Handle command line arguments
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

# Parse arguments
ADDRESS=$1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --epochs)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+:[0-9]+$ ]]; then
                echo -e "${RED}❌ Invalid epochs format. Use: START:END (e.g., 1800:1900)${NC}"
                exit 1
            fi
            EPOCHS_PARAM="&epochs=$2"
            shift 2
            ;;
        --last)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}❌ Invalid number for --last option${NC}"
                exit 1
            fi
            EPOCHS_PARAM="&last=$2"
            shift 2
            ;;
        --set-cookie)
            echo -e "${YELLOW}🍪 Setting up Cloudflare cookie...${NC}"
            echo -e "${BLUE}Go to https://api.mainnet.aztec.network in your browser${NC}"
            echo -e "${BLUE}Open Developer Tools (F12) → Network tab → Refresh page${NC}"
            echo -e "${BLUE}Copy the 'Cookie' header value${NC}"
            echo ""
            echo -n "Enter cookie value: "
            read -r COOKIE
            if [[ -n "$COOKIE" ]]; then
                echo "$COOKIE" > "$COOKIE_FILE"
                echo -e "${GREEN}✅ Cookie saved to $COOKIE_FILE${NC}"
            else
                echo -e "${RED}❌ No cookie provided${NC}"
            fi
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate inputs
check_dependencies
validate_address "$ADDRESS"

# Load cookie if exists
COOKIE_HEADER=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE_HEADER="-H Cookie:$(cat "$COOKIE_FILE")"
    echo -e "${GREEN}🍪 Using saved cookie${NC}"
fi

echo -e "${BOLD}${CYAN}🔍 Fetching validator stats for:${NC} ${YELLOW}$ADDRESS${NC}"
echo ""

# Function to make API calls with better error handling
make_api_call() {
    local url=$1
    local title=$2
    local icon=$3
    local color=$4
    
    echo -e "${BOLD}${color}${icon} ${title}:${NC}"
    
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" $COOKIE_HEADER "$url" 2>/dev/null)
    http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    response=$(echo "$response" | sed -e 's/HTTPSTATUS:.*//g')
    
    if [ "$http_code" -eq 200 ]; then
        if echo "$response" | jq . >/dev/null 2>&1; then
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
        else
            echo -e "${RED}❌ Invalid JSON response${NC}"
        fi
    elif [ "$http_code" -eq 403 ]; then
        echo -e "${RED}❌ Access forbidden - Cloudflare protection active${NC}"
        echo -e "${YELLOW}💡 Try: aztec-stats $ADDRESS --set-cookie${NC}"
    elif [ "$http_code" -eq 404 ]; then
        echo -e "${YELLOW}⚠️  No data found for this validator${NC}"
    else
        echo -e "${RED}❌ API request failed (HTTP $http_code)${NC}"
        echo -e "${YELLOW}Response: $response${NC}"
    fi
    echo ""
}

# Make API calls
make_api_call "$BASE_URL/validators/$ADDRESS/performance?${EPOCHS_PARAM}" "Performance Stats" "📊" "$CYAN"
make_api_call "$BASE_URL/validators/$ADDRESS/accusations" "Accusations" "⚠️ " "$YELLOW"
make_api_call "$BASE_URL/validators/$ADDRESS/slashing" "Slashing Events" "🔨" "$RED"
make_api_call "$BASE_URL/validators/$ADDRESS/committees" "Committee Participation" "👥" "$GREEN"

echo -e "${BOLD}${GREEN}✅ Stats retrieval completed${NC}"
echo -e "${BLUE}💡 Run with --help for more options${NC}"
