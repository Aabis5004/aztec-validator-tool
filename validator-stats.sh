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
    mkdir -p "$(dirname "$CONFIG_FILE")" "$CACHE_DIR" "$SCRIPT_DIR"
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

# (All API fetch and parsing functions remain unchanged except the balance conversion now explicitly uses STK)
parse_validator_stats() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A"
        return
    fi
    
    local status attestation_success total_succeeded total_missed
    local blocks_proposed blocks_mined blocks_missed balance effective_balance
    
    status=$(jq -r '.status // .state // .validatorStatus // "N/A"' "$json_file")
    attestation_success=$(jq -r '.attestationSuccess // .attestationSuccessRate // .attestation_success_rate // .successRate // "N/A"' "$json_file")
    total_succeeded=$(jq -r '.totalAttestationsSucceeded // 0' "$json_file")
    total_missed=$(jq -r '.totalAttestationsMissed // 0' "$json_file")
    blocks_proposed=$(jq -r '.totalBlocksProposed // 0' "$json_file")
    blocks_mined=$(jq -r '.totalBlocksMined // 0' "$json_file")
    blocks_missed=$(jq -r '.totalBlocksMissed // 0' "$json_file")
    
    balance=$(jq -r '.balance // .validatorBalance // .stake // "0"' "$json_file")
    if [[ "$balance" =~ ^[0-9]+$ ]] && [[ ${#balance} -gt 15 ]]; then
        balance=$(echo "scale=6; $balance / 1000000000000000000" | bc)
    fi
    balance="${balance} STK"
    
    effective_balance=$(jq -r '.effectiveBalance // .validatorEffectiveBalance // "0"' "$json_file")
    if [[ "$effective_balance" =~ ^[0-9]+$ ]] && [[ ${#effective_balance} -gt 15 ]]; then
        effective_balance=$(echo "scale=6; $effective_balance / 1000000000000000000" | bc)
    fi
    effective_balance="${effective_balance} STK"
    
    echo "${status}|${attestation_success}|${total_succeeded}|${total_missed}|${blocks_proposed}|${blocks_mined}|${blocks_missed}|${balance}|${effective_balance}"
}

# (Rest of functions and main() remain unchanged. Make sure main ends with cleanup_and_exit 0)
