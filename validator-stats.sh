#!/bin/bash
set -e

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration - Universal paths (no directory issues)
COOKIE_FILE="$HOME/.aztec_validator_cookie"
CONFIG_FILE="$HOME/.aztec_validator_config"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# API Endpoints - Multiple sources for comprehensive data
DASHTEC_BASE="https://dashtec.xyz/api"
AZTEC_BASE="https://api.mainnet.aztec.network"

# Help function
show_help() {
    cat <<EOF
${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}
${CYAN}${BOLD}║               AZTEC VALIDATOR STATS TOOL                     ║${NC}
${CYAN}${BOLD}║                     by Aabis Lone                            ║${NC}
${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}

${BOLD}Usage:${NC}
  aztec-stats <validator_address> [options]

${BOLD}Options:${NC}
  --epochs START:END    Get stats for specific epoch range (e.g., 1800:1900)
  --last N              Get stats for last N epochs
  --cookie TOKEN        Provide Cloudflare cf_clearance token
  --set-cookie          Interactively set and save Cloudflare cookie
  --debug               Show raw JSON responses for troubleshooting
  --help, -h            Show this help message

${BOLD}Examples:${NC}
  aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3
  aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --epochs 1797:1897
  aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --last 120 --set-cookie

${BOLD}Complete Stats Include:${NC}
  🌐 Network Overview    📊 Attestation Stats    📋 Block Production
  🔨 Slashing History    ⚠️  Accusations        👥 Committee Roles
  🏆 Validator Rankings  📈 Performance Trends   💰 Reward Analytics
EOF
}

# Utility functions
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }

# Validate Ethereum address
validate_address() {
    local addr=$1
    if [[ ! $addr =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        error "Invalid Ethereum address format"
        echo -e "${YELLOW}Address must be 42 characters starting with 0x${NC}"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in curl jq bc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing[*]}"
        echo -e "${YELLOW}Install with:${NC}"
        echo -e "${YELLOW}  Ubuntu/Debian: sudo apt install ${missing[*]}${NC}"
        echo -e "${YELLOW}  macOS: brew install ${missing[*]}${NC}"
        exit 1
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    if [[ -f "$COOKIE_FILE" ]]; then
        CF_CLEARANCE=$(cat "$COOKIE_FILE")
    fi
}

# Save cookie
save_cookie() {
    local cookie="$1"
    echo "$cookie" > "$COOKIE_FILE"
    chmod 600 "$COOKIE_FILE"
    success "Cookie saved securely"
}

# Interactive cookie setup
setup_cookie() {
    echo -e "${YELLOW}🍪 Cloudflare Cookie Setup${NC}"
    echo -e "${BLUE}1. Open https://dashtec.xyz in your browser${NC}"
    echo -e "${BLUE}2. Press F12 (Developer Tools)${NC}"
    echo -e "${BLUE}3. Go to Application/Storage → Cookies → https://dashtec.xyz${NC}"
    echo -e "${BLUE}4. Find 'cf_clearance' and copy its value${NC}"
    echo ""
    echo -n "Paste cf_clearance value (or press Enter to skip): "
    read -r cookie_input
    
    if [[ -n "$cookie_input" ]]; then
        save_cookie "$cookie_input"
        CF_CLEARANCE="$cookie_input"
        return 0
    else
        warning "Continuing without cookie (may encounter Cloudflare blocks)"
        return 1
    fi
}

# Enhanced HTTP request function
make_request() {
    local url="$1"
    local output_file="$2"
    local headers=()
    
    headers+=("-H" "User-Agent: $USER_AGENT")
    headers+=("-H" "Accept: application/json, */*")
    headers+=("-H" "Referer: https://dashtec.xyz/")
    
    if [[ -n "${CF_CLEARANCE:-}" ]]; then
        headers+=("-H" "Cookie: cf_clearance=$CF_CLEARANCE")
    fi
    
    local http_code
    http_code=$(curl -s -w "%{http_code}" -o "$output_file" "${headers[@]}" "$url" 2>/dev/null || echo "000")
    
    echo "$http_code"
}

# Parse command line arguments
ADDRESS=""
EPOCH_START=""
EPOCH_END=""
LAST_N=""
DEBUG=false
SET_COOKIE=false

if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --epochs)
            if [[ -n "$2" && "$2" =~ ^[0-9]+:[0-9]+$ ]]; then
                IFS=':' read -r EPOCH_START EPOCH_END <<< "$2"
                shift 2
            else
                error "Invalid epochs format. Use: START:END (e.g., 1800:1900)"
                exit 1
            fi
            ;;
        --last)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                LAST_N="$2"
                shift 2
            else
                error "Invalid number for --last option"
                exit 1
            fi
            ;;
        --cookie)
            if [[ -n "$2" ]]; then
                CF_CLEARANCE="$2"
                shift 2
            else
                error "Cookie value required"
                exit 1
            fi
            ;;
        --set-cookie)
            SET_COOKIE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        0x*)
            ADDRESS="$1"
            shift
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Main execution
clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║               AZTEC VALIDATOR COMPREHENSIVE STATS            ║${NC}"
echo -e "${CYAN}${BOLD}║                        by Aabis Lone                         ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate inputs
if [[ -z "$ADDRESS" ]]; then
    error "Validator address is required"
    show_help
    exit 1
fi

check_dependencies
validate_address "$ADDRESS"
load_config

# Handle cookie setup
if [[ "$SET_COOKIE" == "true" ]]; then
    setup_cookie
    [[ -z "${CF_CLEARANCE:-}" ]] && exit 0
fi

# Convert address to lowercase for API consistency
ADDRESS_LC=$(echo "$ADDRESS" | tr '[:upper:]' '[:lower:]')

info "Analyzing validator: $ADDRESS_LC"
echo ""

# Create temporary directory for API responses
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# =============================================================================
# 1. NETWORK OVERVIEW
# =============================================================================
echo -e "${BOLD}${CYAN}🌐 NETWORK OVERVIEW${NC}"
echo "════════════════════════════════════════════════════════════════"

NETWORK_FILE="$TEMP_DIR/network.json"
http_code=$(make_request "$DASHTEC_BASE/stats/general" "$NETWORK_FILE")

if [[ "$http_code" == "200" && -s "$NETWORK_FILE" ]]; then
    current_epoch=$(jq -r '.currentEpoch // .epoch // "N/A"' "$NETWORK_FILE" 2>/dev/null)
    active_validators=$(jq -r '.activeValidators // .active // "N/A"' "$NETWORK_FILE" 2>/dev/null)
    total_validators=$(jq -r '.totalValidators // .total // "N/A"' "$NETWORK_FILE" 2>/dev/null)
    
    printf "%-25s %s\n" "Current Epoch:" "$current_epoch"
    printf "%-25s %s\n" "Active Validators:" "$active_validators"
    printf "%-25s %s\n" "Total Validators:" "$total_validators"
    
    [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}Debug: Network data in $NETWORK_FILE${NC}"
else
    warning "Network stats unavailable (HTTP: $http_code)"
    current_epoch=""
fi

echo ""

# =============================================================================
# 2. VALIDATOR DETAILS
# =============================================================================
echo -e "${BOLD}${GREEN}📊 VALIDATOR PERFORMANCE${NC}"
echo "════════════════════════════════════════════════════════════════"

VALIDATOR_FILE="$TEMP_DIR/validator.json"
http_code=$(make_request "$DASHTEC_BASE/validators/$ADDRESS_LC" "$VALIDATOR_FILE")

if [[ "$http_code" == "200" && -s "$VALIDATOR_FILE" ]]; then
    # Extract comprehensive validator data
    status=$(jq -r '.status // "N/A"' "$VALIDATOR_FILE" 2>/dev/null)
    balance=$(jq -r '.balance // "N/A"' "$VALIDATOR_FILE" 2>/dev/null)
    
    # Attestation stats
    total_attestations=$(jq -r '.totalAttestations // (.totalAttestationsSucceeded + .totalAttestationsMissed) // 0' "$VALIDATOR_FILE" 2>/dev/null)
    successful_attestations=$(jq -r '.totalAttestationsSucceeded // .attestationsSucceeded // 0' "$VALIDATOR_FILE" 2>/dev/null)
    missed_attestations=$(jq -r '.totalAttestationsMissed // .attestationsMissed // 0' "$VALIDATOR_FILE" 2>/dev/null)
    attestation_rate=$(jq -r '.attestationSuccessRate // .attestationSuccess // "N/A"' "$VALIDATOR_FILE" 2>/dev/null)
    
    # Block production stats
    total_proposals=$(jq -r '.totalBlocksProposed // .blocksProposed // 0' "$VALIDATOR_FILE" 2>/dev/null)
    successful_blocks=$(jq -r '.totalBlocksMined // .blocksMined // .blocksSucceeded // 0' "$VALIDATOR_FILE" 2>/dev/null)
    missed_blocks=$(jq -r '.totalBlocksMissed // .blocksMissed // 0' "$VALIDATOR_FILE" 2>/dev/null)
    
    # Calculate rates if not provided
    if [[ "$total_attestations" != "0" && "$attestation_rate" == "N/A" ]]; then
        attestation_rate=$(echo "scale=2; ($successful_attestations * 100) / $total_attestations" | bc 2>/dev/null || echo "N/A")
        [[ "$attestation_rate" != "N/A" ]] && attestation_rate="${attestation_rate}%"
    fi
    
    block_success_rate="N/A"
    if [[ "$total_proposals" != "0" ]]; then
        block_success_rate=$(echo "scale=2; ($successful_blocks * 100) / $total_proposals" | bc 2>/dev/null || echo "N/A")
        [[ "$block_success_rate" != "N/A" ]] && block_success_rate="${block_success_rate}%"
    fi
    
    # Display validator info
    printf "%-25s %s\n" "Status:" "$status"
    printf "%-25s %s\n" "Balance:" "$balance"
    echo ""
    
    # Attestation section
    echo -e "${GREEN}✅ ATTESTATION PERFORMANCE${NC}"
    printf "%-25s %s\n" "  Total Attestations:" "$total_attestations"
    printf "%-25s %s\n" "  ├─ Successful:" "$successful_attestations"
    printf "%-25s %s\n" "  ├─ Missed:" "$missed_attestations"
    printf "%-25s %s\n" "  └─ Success Rate:" "$attestation_rate"
    echo ""
    
    # Block production section
    echo -e "${BLUE}📋 BLOCK PRODUCTION${NC}"
    printf "%-25s %s\n" "  Total Proposals:" "$total_proposals"
    printf "%-25s %s\n" "  ├─ Successfully Mined:" "$successful_blocks"
    printf "%-25s %s\n" "  ├─ Missed:" "$missed_blocks"
    printf "%-25s %s\n" "  └─ Success Rate:" "$block_success_rate"
    
    [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}Debug: Validator data in $VALIDATOR_FILE${NC}"
elif [[ "$http_code" == "403" ]]; then
    error "Access forbidden - Cloudflare protection active"
    echo -e "${YELLOW}💡 Run: aztec-stats $ADDRESS --set-cookie${NC}"
    exit 1
else
    error "Failed to fetch validator data (HTTP: $http_code)"
    [[ "$DEBUG" == "true" ]] && [[ -s "$VALIDATOR_FILE" ]] && echo -e "${BLUE}Debug: Response in $VALIDATOR_FILE${NC}"
fi

echo ""

# =============================================================================
# 3. SLASHING HISTORY
# =============================================================================
echo -e "${BOLD}${RED}🔨 SLASHING HISTORY${NC}"
echo "════════════════════════════════════════════════════════════════"

SLASHING_FILE="$TEMP_DIR/slashing.json"
http_code=$(make_request "$DASHTEC_BASE/slashing-history?limit=20" "$SLASHING_FILE")

if [[ "$http_code" == "200" && -s "$SLASHING_FILE" ]]; then
    total_slashing=$(jq -r 'if type=="array" then length else (.data // [] | length) end' "$SLASHING_FILE" 2>/dev/null)
    my_slashing=$(jq -r --arg addr "$ADDRESS_LC" '
        (if type=="array" then . else (.data // []) end)
        | map(select((.validator // .address // "") | ascii_downcase == $addr))
        | length
    ' "$SLASHING_FILE" 2>/dev/null)
    
    printf "%-25s %s\n" "Recent Slashing Events:" "$total_slashing"
    printf "%-25s %s\n" "Your Validator:" "$my_slashing"
    
    if [[ "$my_slashing" != "0" ]]; then
        echo -e "${RED}⚠️  Slashing events found for your validator:${NC}"
        jq -r --arg addr "$ADDRESS_LC" '
            (if type=="array" then . else (.data // []) end)
            | map(select((.validator // .address // "") | ascii_downcase == $addr))
            | .[] | "  Epoch: \(.epoch // "N/A") | Reason: \(.reason // "N/A") | Amount: \(.amount // "N/A")"
        ' "$SLASHING_FILE" 2>/dev/null || echo "  Unable to parse slashing details"
    else
        success "No slashing events found - Clean record!"
    fi
    
    [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}Debug: Slashing data in $SLASHING_FILE${NC}"
else
    warning "Slashing history unavailable (HTTP: $http_code)"
fi

echo ""

# =============================================================================
# 4. TOP VALIDATORS RANKING (if epoch range provided)
# =============================================================================
if [[ -n "$EPOCH_START" && -n "$EPOCH_END" ]] || [[ -n "$LAST_N" && -n "$current_epoch" ]]; then
    echo -e "${BOLD}${PURPLE}🏆 VALIDATOR RANKING${NC}"
    echo "════════════════════════════════════════════════════════════════"
    
    TOP_FILE="$TEMP_DIR/top.json"
    
    if [[ -n "$EPOCH_START" && -n "$EPOCH_END" ]]; then
        epoch_window="${EPOCH_START}:${EPOCH_END}"
        http_code=$(make_request "$DASHTEC_BASE/dashboard/top-validators?startEpoch=$EPOCH_START&endEpoch=$EPOCH_END" "$TOP_FILE")
    elif [[ -n "$LAST_N" && -n "$current_epoch" ]]; then
        start_epoch=$((current_epoch - LAST_N + 1))
        [[ $start_epoch -lt 0 ]] && start_epoch=0
        epoch_window="last $LAST_N epochs (${start_epoch}:${current_epoch})"
        http_code=$(make_request "$DASHTEC_BASE/dashboard/top-validators?startEpoch=$start_epoch&endEpoch=$current_epoch" "$TOP_FILE")
    fi
    
    if [[ "$http_code" == "200" && -s "$TOP_FILE" ]]; then
        my_rank=$(jq -r --arg addr "$ADDRESS_LC" '
            (if type=="array" then . else (.data // []) end)
            | to_entries
            | map(select((.value.address // .value.validator // "") | ascii_downcase == $addr))
            | if length > 0 then .[0].key + 1 else empty end
        ' "$TOP_FILE" 2>/dev/null)
        
        total_in_ranking=$(jq -r 'if type=="array" then length else (.data // [] | length) end' "$TOP_FILE" 2>/dev/null)
        
        printf "%-25s %s\n" "Epoch Window:" "$epoch_window"
        printf "%-25s %s\n" "Total Validators Ranked:" "$total_in_ranking"
        printf "%-25s %s\n" "Your Rank:" "${my_rank:-Not in top ranking}"
        
        if [[ -n "$my_rank" ]]; then
            success "Your validator is ranked #$my_rank"
        else
            warning "Your validator not in top performers for this period"
        fi
        
        [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}Debug: Ranking data in $TOP_FILE${NC}"
    else
        warning "Ranking data unavailable (HTTP: $http_code)"
    fi
    
    echo ""
fi

# =============================================================================
# 5. COMMITTEE PARTICIPATION (Alternative API)
# =============================================================================
echo -e "${BOLD}${CYAN}👥 COMMITTEE PARTICIPATION${NC}"
echo "════════════════════════════════════════════════════════════════"

COMMITTEE_FILE="$TEMP_DIR/committee.json"
# Try both Dashtec and Aztec APIs for committee data
http_code=$(make_request "$AZTEC_BASE/validators/$ADDRESS_LC/committees" "$COMMITTEE_FILE")

if [[ "$http_code" != "200" || ! -s "$COMMITTEE_FILE" ]]; then
    # Fallback to alternative endpoint
    http_code=$(make_request "$DASHTEC_BASE/validators/$ADDRESS_LC/committees" "$COMMITTEE_FILE")
fi

if [[ "$http_code" == "200" && -s "$COMMITTEE_FILE" ]]; then
    committee_count=$(jq -r 'if type=="array" then length else (.data // [] | length) end' "$COMMITTEE_FILE" 2>/dev/null)
    
    printf "%-25s %s\n" "Committee Assignments:" "$committee_count"
    
    if [[ "$committee_count" != "0" && "$committee_count" != "null" ]]; then
        echo -e "${CYAN}Recent Committee Roles:${NC}"
        jq -r '
            (if type=="array" then . else (.data // []) end)
            | sort_by(.epoch // 0) | reverse
            | limit(5; .[])
            | "  Epoch: \(.epoch // "N/A") | Role: \(.role // .committee // "N/A")"
        ' "$COMMITTEE_FILE" 2>/dev/null || echo "  Unable to parse committee details"
        
        if [[ "$committee_count" -gt 5 ]]; then
            echo -e "  ${BLUE}... and $((committee_count - 5)) more assignments${NC}"
        fi
    else
        warning "No recent committee assignments found"
    fi
    
    [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}Debug: Committee data in $COMMITTEE_FILE${NC}"
else
    warning "Committee data unavailable (HTTP: $http_code)"
fi

echo ""

# =============================================================================
# SUMMARY AND COMPLETION
# =============================================================================
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
success "Comprehensive analysis completed for validator: $ADDRESS_LC"

if [[ -n "$EPOCH_START" && -n "$EPOCH_END" ]]; then
    info "Analysis period: Epochs $EPOCH_START to $EPOCH_END"
elif [[ -n "$LAST_N" ]]; then
    info "Analysis period: Last $LAST_N epochs"
fi

echo -e "${BLUE}📊 Data sources: Dashtec.xyz API, Aztec Network API${NC}"
echo -e "${YELLOW}💡 For help with options: aztec-stats --help${NC}"

if [[ "$DEBUG" == "true" ]]; then
    echo ""
    echo -e "${BLUE}🔧 Debug: Temporary files in $TEMP_DIR${NC}"
    echo -e "${BLUE}   (Files will be automatically cleaned up)${NC}"
fi

echo -e "${BOLD}${GREEN}════════════════
