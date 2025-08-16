#!/usr/bin/env bash
# Enhanced Aztec Validator Stats Tool
# Author: Aabis Lone (Enhanced)
# Features: Network stats, validator details, slashing history, top validators, accusations

set -Eeuo pipefail

# Colors and styling
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
debug() { [[ $DEBUG -eq 1 ]] && echo -e "${CYAN}🔍${NC} $*" || true; }
highlight() { echo -e "${BOLD}$*${NC}"; }

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${HOME}/.config/aztec-validator/config.conf"
readonly CACHE_DIR="${HOME}/.cache/aztec-validator"
readonly LOG_FILE="${CACHE_DIR}/aztec-validator.log"

# API Configuration
readonly DASHTEC_HOST="https://dashtec.xyz"
readonly API_VALIDATOR="${DASHTEC_HOST}/api/validators"
readonly API_GENERAL="${DASHTEC_HOST}/api/stats/general"
readonly API_SLASHING="${DASHTEC_HOST}/api/slashing-history"
readonly API_TOP="${DASHTEC_HOST}/api/dashboard/top-validators"
readonly API_ACCUSATIONS="${DASHTEC_HOST}/api/accusations"

# Default values
readonly UA_DEFAULT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
readonly DEFAULT_REFERER="https://dashtec.xyz/"

# Global variables
CF_CLEARANCE="${CF_CLEARANCE:-}"
USER_AGENT="${USER_AGENT:-$UA_DEFAULT}"
DEBUG=0
VERBOSE=0
SHOW_RAW=0

# Error handling
trap 'cleanup_and_exit 1 "Unexpected error occurred"' ERR

cleanup_and_exit() {
    local exit_code=${1:-0}
    local message=${2:-""}
    
    [[ -n "$message" ]] && error "$message"
    [[ -d "${tmpdir:-}" ]] && rm -rf "$tmpdir"
    exit "$exit_code"
}

# OS Detection
detect_os() {
    case "${OSTYPE:-}" in
        linux-gnu*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        darwin*) echo "mac" ;;
        *) echo "unknown" ;;
    esac
}

# Dependency management
check_dependencies() {
    local missing=()
    local required_tools=("curl" "jq" "bc")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing[*]}"
        install_dependencies "${missing[@]}"
    fi
}

install_dependencies() {
    local deps=("$@")
    local os
    os=$(detect_os)
    
    info "Installing dependencies: ${deps[*]}"
    
    case "$os" in
        wsl|linux)
            if command -v apt >/dev/null 2>&1; then
                sudo apt update && sudo apt install -y "${deps[@]}"
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y "${deps[@]}"
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y "${deps[@]}"
            else
                error "No supported package manager found"
                return 1
            fi
            ;;
        mac)
            if ! command -v brew >/dev/null 2>&1; then
                error "Homebrew not found. Install from: https://brew.sh"
                return 1
            fi
            brew install "${deps[@]}"
            ;;
        *)
            error "Unsupported OS: ${os}"
            return 1
            ;;
    esac
    
    success "Dependencies installed successfully"
}

# Configuration management
create_directories() {
    mkdir -p "$(dirname "$CONFIG_FILE")" "$CACHE_DIR"
}

load_config() {
    create_directories
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        debug "Config loaded from $CONFIG_FILE"
    fi
    
    # Environment variables override config file
    CF_CLEARANCE="${CF_CLEARANCE:-${CF_CLEARANCE_CONFIG:-}}"
    USER_AGENT="${USER_AGENT:-${USER_AGENT_CONFIG:-$UA_DEFAULT}}"
}

save_config() {
    create_directories
    
    cat > "$CONFIG_FILE" <<EOF
# Aztec Validator Tool Configuration
# Generated on $(date)
CF_CLEARANCE_CONFIG='${CF_CLEARANCE}'
USER_AGENT_CONFIG='${USER_AGENT}'
EOF
    
    success "Configuration saved to $CONFIG_FILE"
}

prompt_cookie() {
    echo ""
    highlight "Cloudflare Cookie Setup"
    echo "To get your cf_clearance cookie:"
    echo "1. Open https://dashtec.xyz in Chrome"
    echo "2. Press F12 → Application tab → Cookies → https://dashtec.xyz"
    echo "3. Copy the 'cf_clearance' value"
    echo ""
    
    read -r -p "Paste cf_clearance (or press Enter to skip): " CF_INPUT || true
    
    if [[ -n "${CF_INPUT:-}" ]]; then
        CF_CLEARANCE="$CF_INPUT"
        save_config
        success "Cookie saved and will be used for future requests"
    else
        warn "Continuing without cf_clearance (requests may be blocked)"
    fi
}

# HTTP utilities
http_request() {
    local url="$1"
    local output_file="$2"
    local method="${3:-GET}"
    
    local -a curl_args=(
        -sSL
        -X "$method"
        -H "User-Agent: ${USER_AGENT}"
        -H "Accept: application/json, */*"
        -H "Referer: ${DEFAULT_REFERER}"
        -w '%{http_code}'
        -o "$output_file"
        --connect-timeout 30
        --max-time 60
    )
    
    [[ -n "${CF_CLEARANCE:-}" ]] && curl_args+=(-H "Cookie: cf_clearance=${CF_CLEARANCE}")
    
    debug "Making $method request to: $url"
    
    local http_code
    http_code=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo "000")
    
    debug "HTTP response code: $http_code"
    echo "$http_code"
}

is_valid_json() {
    [[ -f "$1" ]] && jq -e . >/dev/null 2>&1 < "$1"
}

# Address validation
validate_address() {
    local addr="$1"
    local addr_lower
    addr_lower=$(echo "$addr" | tr 'A-F' 'a-f')
    
    if [[ ! "$addr_lower" =~ ^0x[0-9a-f]{40}$ ]]; then
        error "Invalid Ethereum address format"
        error "Expected: 0x followed by 40 hexadecimal characters"
        error "Received: $addr"
        return 1
    fi
    
    echo "$addr_lower"
}

# API data fetchers
fetch_network_stats() {
    local output_file="$1"
    local http_code
    
    info "Fetching network statistics..."
    http_code=$(http_request "$API_GENERAL" "$output_file")
    
    if [[ "$http_code" == "200" && -s "$output_file" ]] && is_valid_json "$output_file"; then
        success "Network stats retrieved"
        return 0
    else
        warn "Failed to fetch network stats (HTTP $http_code)"
        return 1
    fi
}

fetch_validator_stats() {
    local address="$1"
    local output_file="$2"
    local http_code
    
    info "Fetching validator data for: $address"
    http_code=$(http_request "${API_VALIDATOR}/${address}" "$output_file")
    
    if [[ "$http_code" == "200" && -s "$output_file" ]] && is_valid_json "$output_file"; then
        success "Validator stats retrieved"
        return 0
    else
        error "Failed to fetch validator stats (HTTP $http_code)"
        [[ $SHOW_RAW -eq 1 ]] && { echo "--- RAW RESPONSE ---"; cat "$output_file" 2>/dev/null || true; }
        return 1
    fi
}

fetch_slashing_history() {
    local output_file="$1"
    local limit="${2:-50}"
    local http_code
    
    info "Fetching slashing history (last $limit events)..."
    http_code=$(http_request "${API_SLASHING}?page=1&limit=$limit" "$output_file")
    
    if [[ "$http_code" == "200" && -s "$output_file" ]] && is_valid_json "$output_file"; then
        success "Slashing history retrieved"
        return 0
    else
        warn "Failed to fetch slashing history (HTTP $http_code)"
        return 1
    fi
}

fetch_top_validators() {
    local output_file="$1"
    local start_epoch="$2"
    local end_epoch="$3"
    local http_code
    
    info "Fetching top validators for epochs ${start_epoch}:${end_epoch}..."
    http_code=$(http_request "${API_TOP}?startEpoch=${start_epoch}&endEpoch=${end_epoch}" "$output_file")
    
    if [[ "$http_code" == "200" && -s "$output_file" ]] && is_valid_json "$output_file"; then
        success "Top validators data retrieved"
        return 0
    else
        warn "Failed to fetch top validators (HTTP $http_code)"
        return 1
    fi
}

fetch_accusations() {
    local address="$1"
    local output_file="$2"
    local http_code
    
    info "Fetching accusations for validator: $address"
    http_code=$(http_request "${API_ACCUSATIONS}/${address}" "$output_file")
    
    if [[ "$http_code" == "200" && -s "$output_file" ]] && is_valid_json "$output_file"; then
        success "Accusations data retrieved"
        return 0
    else
        warn "Failed to fetch accusations (HTTP $http_code)"
        return 1
    fi
}

# Data processing and display
parse_network_stats() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "N/A|N/A|N/A|N/A"
        return
    fi
    
    local current_epoch active_validators total_validators finalized_epoch
    
    current_epoch=$(jq -r '
        .currentEpoch // 
        .epoch // 
        .latestEpoch // 
        .current_epoch //
        .latest_epoch //
        .headEpoch //
        .head_epoch //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    active_validators=$(jq -r '
        .activeValidators // 
        .validators.active // 
        .active // 
        .active_validators //
        .validatorsActive //
        .validators_active //
        .activeValidatorCount //
        .active_validator_count //
        .activeSequencers //
        .active_sequencers //
        .sequencersActive //
        .sequencers_active //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    total_validators=$(jq -r '
        .totalValidators // 
        .validators.total // 
        .total // 
        .total_validators //
        .validatorsTotal //
        .validators_total //
        .totalValidatorCount //
        .total_validator_count //
        .totalSequencers //
        .total_sequencers //
        .sequencersTotal //
        .sequencers_total //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    finalized_epoch=$(jq -r '
        .finalizedEpoch // 
        .finalized // 
        .finalized_epoch //
        .justifiedEpoch //
        .justified_epoch //
        .lastFinalizedEpoch //
        .last_finalized_epoch //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    echo "${current_epoch}|${active_validators}|${total_validators}|${finalized_epoch}"
}

parse_validator_stats() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A"
        return
    fi
    
    local status attestation_success total_succeeded total_missed
    local blocks_proposed blocks_mined blocks_missed balance effective_balance
    
    # Parse status
    status=$(jq -r '
        .status // 
        .state // 
        .validatorStatus //
        .validator_status //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Parse attestation success rate
    attestation_success=$(jq -r '
        .attestationSuccess // 
        .attestationSuccessRate //
        .attestation_success_rate //
        .successRate //
        .success_rate //
        (.totalAttestationsSucceeded / (.totalAttestationsSucceeded + .totalAttestationsMissed) * 100 | tostring + "%") //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    total_succeeded=$(jq -r '
        .totalAttestationsSucceeded // 
        .attestationsSucceeded //
        .attestations_succeeded //
        .successfulAttestations //
        .successful_attestations //
        0' "$json_file" 2>/dev/null || echo "0")
    
    total_missed=$(jq -r '
        .totalAttestationsMissed // 
        .attestationsMissed //
        .attestations_missed //
        .missedAttestations //
        .missed_attestations //
        0' "$json_file" 2>/dev/null || echo "0")
    
    # Parse block counts
    blocks_proposed=$(jq -r '
        .totalBlocksProposed // 
        .blocksProposed //
        .blocks_proposed //
        .proposedBlocks //
        .proposed_blocks //
        0' "$json_file" 2>/dev/null || echo "0")
    
    blocks_mined=$(jq -r '
        .totalBlocksMined // 
        .blocksMined //
        .blocks_mined //
        .minedBlocks //
        .mined_blocks //
        0' "$json_file" 2>/dev/null || echo "0")
    
    blocks_missed=$(jq -r '
        .totalBlocksMissed // 
        .blocksMissed //
        .blocks_missed //
        .missedBlocks //
        .missed_blocks //
        0' "$json_file" 2>/dev/null || echo "0")
    
    # Parse balance and always display STK
    balance=$(jq -r '
        .balance // 
        .validatorBalance //
        .validator_balance //
        .stake //
        .stakedAmount //
        .staked_amount //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")

    if [[ "$balance" =~ ^[0-9]+$ ]] && [[ ${#balance} -gt 15 ]]; then
        balance=$(echo "scale=6; $
