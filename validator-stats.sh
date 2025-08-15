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

# Help function
show_help() {
    echo -e "${CYAN}${BOLD}Aztec Validator Stats Tool${NC}"
    echo -e "${CYAN}by Aabis Lone${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  aztec-stats <validator_address> [options]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  --last N             Get stats for last N epochs (default: 100)"
    echo -e "  --set-cookie         Set Cloudflare cookie (interactive)"
    echo -e "  --help, -h           Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
    echo -e "  aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --last 200"
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

# Handle arguments properly
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

ADDRESS=""
LAST_EPOCHS=100

# Parse arguments correctly
while [[ $# -gt 0 ]]; do
    case $1 in
        --last)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}❌ Invalid number for --last option${NC}"
                exit 1
            fi
            LAST_EPOCHS=$2
            shift 2
            ;;
        --set-cookie)
            echo -e "${YELLOW}🍪 Setting up Cloudflare cookie...${NC}"
            echo -e "${BLUE}1. Go to https://api.mainnet.aztec.network in your browser${NC}"
            echo -e "${BLUE}2. Open Developer Tools (F12) → Network tab${NC}"
            echo -e "${BLUE}3. Refresh the page${NC}"
            echo -e "${BLUE}4. Find any request and copy the 'Cookie' header value${NC}"
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

# Validate inputs
if [[ -z "$ADDRESS" ]]; then
    echo -e "${RED}❌ Validator address is required${NC}"
    show_help
    exit 1
fi

check_dependencies
validate_address "$ADDRESS"

# Load cookie if exists
COOKIE_HEADER=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE_HEADER="-H Cookie:$(cat "$COOKIE_FILE")"
    echo -e "${GREEN}🍪 Using saved cookie${NC}"
fi

echo -e "${BOLD}${CYAN}🔍 Fetching validator stats for:${NC} ${YELLOW}$ADDRESS${NC}"
echo -e "${BLUE}📊 Analyzing last $LAST_EPOCHS epochs${NC}"
echo ""

# Function to make API calls with better error handling
make_api_call() {
    local url=$1
    
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" $COOKIE_HEADER "$url" 2>/dev/null)
    http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    response=$(echo "$response" | sed -e 's/HTTPSTATUS:.*//g')
    
    if [ "$http_code" -eq 200 ]; then
        echo "$response"
        return 0
    elif [ "$http_code" -eq 403 ]; then
        echo -e "${RED}❌ Access forbidden - Cloudflare protection active${NC}"
        echo -e "${YELLOW}💡 Run: aztec-stats $ADDRESS --set-cookie${NC}"
        exit 1
    elif [ "$http_code" -eq 404 ]; then
        echo -e "${YELLOW}⚠️  No data found for this validator${NC}"
        return 1
    else
        echo -e "${RED}❌ API request failed (HTTP $http_code)${NC}"
        return 1
    fi
}

# Get performance data
echo -e "${BOLD}${CYAN}📈 VALIDATOR PERFORMANCE SUMMARY${NC}"
echo "=================================================="

performance_data=$(make_api_call "$BASE_URL/validators/$ADDRESS/performance?last=$LAST_EPOCHS")

if [[ $? -eq 0 ]] && [[ -n "$performance_data" ]]; then
    # Parse performance data with better error handling
    total_attestations=$(echo "$performance_data" | jq -r '.totalAttestations // "N/A"' 2>/dev/null)
    missed_attestations=$(echo "$performance_data" | jq -r '.missedAttestations // "N/A"' 2>/dev/null)
    total_proposals=$(echo "$performance_data" | jq -r '.totalProposals // "N/A"' 2>/dev/null)
    missed_proposals=$(echo "$performance_data" | jq -r '.missedProposals // "N/A"' 2>/dev/null)
    success_rate=$(echo "$performance_data" | jq -r '.successRate // "N/A"' 2>/dev/null)
    
    # Calculate additional metrics
    if [[ "$total_attestations" != "N/A" && "$missed_attestations" != "N/A" ]]; then
        successful_attestations=$((total_attestations - missed_attestations))
        if [[ $total_attestations -gt 0 ]]; then
            attestation_rate=$(echo "scale=2; ($successful_attestations * 100) / $total_attestations" | bc 2>/dev/null || echo "N/A")
        else
            attestation_rate="N/A"
        fi
    else
        successful_attestations="N/A"
        attestation_rate="N/A"
    fi
    
    if [[ "$total_proposals" != "N/A" && "$missed_proposals" != "N/A" ]]; then
        successful_proposals=$((total_proposals - missed_proposals))
        if [[ $total_proposals -gt 0 ]]; then
            proposal_rate=$(echo "scale=2; ($successful_proposals * 100) / $total_proposals" | bc 2>/dev/null || echo "N/A")
        else
            proposal_rate="N/A"
        fi
    else
        successful_proposals="N/A"
        proposal_rate="N/A"
    fi
    
    # Display formatted results
    echo -e "${GREEN}✅ ATTESTATIONS:${NC}"
    echo -e "   Total Attestations: ${BOLD}$total_attestations${NC}"
    echo -e "   Successful: ${BOLD}${GREEN}$successful_attestations${NC}"
    echo -e "   Missed: ${BOLD}${RED}$missed_attestations${NC}"
    echo -e "   Success Rate: ${BOLD}${attestation_rate}%${NC}"
    echo ""
    
    echo -e "${BLUE}📋 BLOCK PROPOSALS:${NC}"
    echo -e "   Total Proposals: ${BOLD}$total_proposals${NC}"
    echo -e "   Successful: ${BOLD}${GREEN}$successful_proposals${NC}"
    echo -e "   Missed: ${BOLD}${RED}$missed_proposals${NC}"
    echo -e "   Success Rate: ${BOLD}${proposal_rate}%${NC}"
    echo ""
    
    echo -e "${CYAN}🎯 OVERALL PERFORMANCE:${NC}"
    echo -e "   Overall Success Rate: ${BOLD}${success_rate}%${NC}"
    echo ""
else
    echo -e "${RED}❌ Could not fetch performance data${NC}"
fi

# Get slashing data
echo -e "${BOLD}${RED}🔨 SLASHING EVENTS${NC}"
echo "=================================================="

slashing_data=$(make_api_call "$BASE_URL/validators/$ADDRESS/slashing")

if [[ $? -eq 0 ]] && [[ -n "$slashing_data" ]]; then
    slashing_count=$(echo "$slashing_data" | jq -r '. | length' 2>/dev/null)
    
    if [[ "$slashing_count" == "0" ]]; then
        echo -e "${GREEN}✅ No slashing events found - Clean record!${NC}"
    else
        echo -e "${RED}⚠️  Found $slashing_count slashing event(s)${NC}"
        echo "$slashing_data" | jq -r '.[] | "   Epoch: \(.epoch // "N/A") | Reason: \(.reason // "N/A") | Amount: \(.amount // "N/A")"' 2>/dev/null
    fi
else
    echo -e "${GREEN}✅ No slashing data (likely clean record)${NC}"
fi

echo ""

# Get accusations data
echo -e "${BOLD}${YELLOW}⚠️  ACCUSATIONS${NC}"
echo "=================================================="

accusations_data=$(make_api_call "$BASE_URL/validators/$ADDRESS/accusations")

if [[ $? -eq 0 ]] && [[ -n "$accusations_data" ]]; then
    accusations_count=$(echo "$accusations_data" | jq -r '. | length' 2>/dev/null)
    
    if [[ "$accusations_count" == "0" ]]; then
        echo -e "${GREEN}✅ No accusations found - Clean record!${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $accusations_count accusation(s)${NC}"
        echo "$accusations_data" | jq -r '.[] | "   Epoch: \(.epoch // "N/A") | Type: \(.type // "N/A") | Status: \(.status // "N/A")"' 2>/dev/null
    fi
else
    echo -e "${GREEN}✅ No accusations data (likely clean record)${NC}"
fi

echo ""

# Get committee participation
echo -e "${BOLD}${GREEN}👥 COMMITTEE PARTICIPATION${NC}"
echo "=================================================="

committee_data=$(make_api_call "$BASE_URL/validators/$ADDRESS/committees")

if [[ $? -eq 0 ]] && [[ -n "$committee_data" ]]; then
    committee_count=$(echo "$committee_data" | jq -r '. | length' 2>/dev/null)
    echo -e "${GREEN}📊 Committee assignments: ${BOLD}$committee_count${NC}"
    
    if [[ "$committee_count" != "0" && "$committee_count" != "null" ]]; then
        echo "$committee_data" | jq -r '.[] | "   Epoch: \(.epoch // "N/A") | Role: \(.role // "N/A") | Committee: \(.committee // "N/A")"' 2>/dev/null | head -10
        
        if [[ "$committee_count" -gt 10 ]]; then
            echo -e "   ${BLUE}... and $((committee_count - 10)) more assignments${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  No committee data available${NC}"
fi

echo ""
echo -e "${BOLD}${GREEN}✅ Analysis completed for last $LAST_EPOCHS epochs${NC}"
echo -e "${BLUE}💡 Run with --help for more options${NC}"
