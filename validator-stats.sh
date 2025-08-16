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
    
    debug "Parsing network stats from: $json_file"
    [[ $DEBUG -eq 1 ]] && echo "Network JSON content:" && jq '.' "$json_file" 2>/dev/null || true
    
    local current_epoch active_validators total_validators finalized_epoch
    
    # Try multiple possible field names for current epoch
    current_epoch=$(jq -r '
        .currentEpoch // 
        .epoch // 
        .latestEpoch // 
        .current_epoch //
        .latest_epoch //
        .headEpoch //
        .head_epoch //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Try multiple possible field names for active validators  
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
    
    # Try multiple possible field names for total validators
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
    
    # Try multiple possible field names for finalized epoch
    finalized_epoch=$(jq -r '
        .finalizedEpoch // 
        .finalized // 
        .finalized_epoch //
        .justifiedEpoch //
        .justified_epoch //
        .lastFinalizedEpoch //
        .last_finalized_epoch //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    debug "Parsed network stats: epoch=$current_epoch, active=$active_validators, total=$total_validators, finalized=$finalized_epoch"
    
    echo "${current_epoch}|${active_validators}|${total_validators}|${finalized_epoch}"
}

parse_validator_stats() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A|N/A"
        return
    fi
    
    debug "Parsing validator stats from: $json_file"
    [[ $DEBUG -eq 1 ]] && echo "Validator JSON content:" && jq '.' "$json_file" 2>/dev/null || true
    
    local status attestation_success total_succeeded total_missed
    local blocks_proposed blocks_mined blocks_missed balance effective_balance
    
    # Parse status
    status=$(jq -r '
        .status // 
        .state // 
        .validatorStatus //
        .validator_status //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Parse attestation success rate - try percentage and decimal formats
    attestation_success=$(jq -r '
        .attestationSuccess // 
        .attestationSuccessRate //
        .attestation_success_rate //
        .successRate //
        .success_rate //
        (.totalAttestationsSucceeded / (.totalAttestationsSucceeded + .totalAttestationsMissed) * 100 | tostring + "%") //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Parse attestation counts
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
    
    # Parse balance - handle Aztec token format (not ETH)
    balance=$(jq -r '
        .balance // 
        .validatorBalance //
        .validator_balance //
        .stake //
        .stakedAmount //
        .staked_amount //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Convert balance from smallest unit to main token if it's a large number
    if [[ "$balance" =~ ^[0-9]+$ ]] && [[ ${#balance} -gt 15 ]]; then
        # Large number - likely in smallest unit, convert to main token (assuming 18 decimals)
        balance=$(echo "scale=6; $balance / 1000000000000000000" | bc 2>/dev/null || echo "$balance")
        balance="${balance} AZTEC"
    elif [[ "$balance" =~ ^[0-9]+$ ]] && [[ ${#balance} -gt 6 ]]; then
        # Medium number - might need conversion or could be in different unit
        balance="${balance} tokens"
    elif [[ "$balance" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Already decimal format
        balance="${balance} AZTEC"
    fi
    
    effective_balance=$(jq -r '
        .effectiveBalance // 
        .effective_balance //
        .validatorEffectiveBalance //
        .validator_effective_balance //
        .effectiveStake //
        .effective_stake //
        "N/A"' "$json_file" 2>/dev/null || echo "N/A")
    
    # Convert effective balance similar to regular balance
    if [[ "$effective_balance" =~ ^[0-9]+$ ]] && [[ ${#effective_balance} -gt 15 ]]; then
        effective_balance=$(echo "scale=6; $effective_balance / 1000000000000000000" | bc 2>/dev/null || echo "$effective_balance")
        effective_balance="${effective_balance} AZTEC"
    elif [[ "$effective_balance" =~ ^[0-9]+$ ]] && [[ ${#effective_balance} -gt 6 ]]; then
        effective_balance="${effective_balance} tokens"
    elif [[ "$effective_balance" =~ ^[0-9]+\.[0-9]+$ ]]; then
        effective_balance="${effective_balance} AZTEC"
    fi
    
    debug "Parsed validator stats: status=$status, success=$attestation_success, succeeded=$total_succeeded, missed=$total_missed"
    
    echo "${status}|${attestation_success}|${total_succeeded}|${total_missed}|${blocks_proposed}|${blocks_mined}|${blocks_missed}|${balance}|${effective_balance}"
}

parse_slashing_history() {
    local json_file="$1"
    local validator_address="$2"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "0|0|N/A"
        return
    fi
    
    debug "Parsing slashing history from: $json_file for validator: $validator_address"
    [[ $DEBUG -eq 1 ]] && echo "Slashing JSON content:" && jq '.' "$json_file" 2>/dev/null || true
    
    local total_events validator_slashes recent_event
    
    # Handle both array format and object with data field
    total_events=$(jq -r '
        if type=="array" then 
            length 
        else 
            (.data // [] | length) // 
            (.slashings // [] | length) // 
            (.events // [] | length) // 
            0 
        end' "$json_file" 2>/dev/null || echo "0")
    
    # Find slashing events for this validator (try multiple field names)
    validator_slashes=$(jq -r --arg addr "$validator_address" '
        def get_events:
            if type=="array" then . 
            else (.data // .slashings // .events // []) end;
        
        get_events
        | if type=="array" then
            [ .[] | select(
                (.validator // .address // .pubkey // .validatorAddress // .validator_address // "") 
                | ascii_downcase == ($addr | ascii_downcase)
            )] | length
          else 0 end
    ' "$json_file" 2>/dev/null || echo "0")
    
    # Get most recent event info (epoch/slot/block)
    recent_event=$(jq -r '
        def get_events:
            if type=="array" then . 
            else (.data // .slashings // .events // []) end;
        
        get_events
        | if type=="array" and length > 0 then
            .[0] | (
                .epoch // 
                .slot // 
                .block // 
                .blockNumber // 
                .block_number //
                .slotNumber //
                .slot_number //
                "N/A"
            )
          else "N/A" end
    ' "$json_file" 2>/dev/null || echo "N/A")
    
    debug "Parsed slashing stats: total=$total_events, validator_hits=$validator_slashes, recent=$recent_event"
    
    echo "${total_events}|${validator_slashes}|${recent_event}"
}

find_validator_rank() {
    local json_file="$1"
    local validator_address="$2"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        echo "N/A"
        return
    fi
    
    jq -r --arg addr "$validator_address" '
        def as_list: if type=="array" then . else .data // [] end;
        as_list
        | to_entries
        | map(select(
            (.value.address // .value.validator // .value.pubkey // "") | ascii_downcase == ($addr | ascii_downcase)
        ))
        | if length > 0 then .[0].key + 1 else "Not ranked" end
    ' "$json_file" 2>/dev/null || echo "N/A"
}

# Display functions
print_header() {
    clear || true
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            🔍 ENHANCED AZTEC VALIDATOR STATS 🔍              ║"
    echo "║                     by Aabis Lone                           ║"
    echo "║               Enhanced with Full Features                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

print_network_stats() {
    local stats="$1"
    IFS='|' read -r current_epoch active_validators total_validators finalized_epoch <<< "$stats"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                        NETWORK OVERVIEW                      ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "🌐 Current Epoch:" "$current_epoch"
    printf "%-25s %s\n" "📊 Active Validators:" "$active_validators"
    printf "%-25s %s\n" "📈 Total Validators:" "$total_validators"
    printf "%-25s %s\n" "✅ Finalized Epoch:" "$finalized_epoch"
}

print_validator_stats() {
    local address="$1"
    local stats="$2"
    IFS='|' read -r status attestation_success total_succeeded total_missed blocks_proposed blocks_mined blocks_missed balance effective_balance <<< "$stats"
    
    local total_attestations=$((total_succeeded + total_missed))
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                      VALIDATOR DETAILS                       ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "🔑 Address:" "$address"
    printf "%-25s %s\n" "📊 Status:" "$status"
    printf "%-25s %s\n" "💰 Staked Balance:" "$balance"
    printf "%-25s %s\n" "⚖️  Effective Balance:" "$effective_balance"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                    ATTESTATION PERFORMANCE                   ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "🎯 Success Rate:" "$attestation_success"
    printf "%-25s %s\n" "📊 Total Attestations:" "$total_attestations"
    printf "%-25s %s\n" "  ├─ ✅ Succeeded:" "$total_succeeded"
    printf "%-25s %s\n" "  └─ ❌ Missed:" "$total_missed"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                       BLOCK PERFORMANCE                      ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "🏗️  Blocks Proposed:" "$blocks_proposed"
    printf "%-25s %s\n" "⛏️  Blocks Mined:" "$blocks_mined"
    printf "%-25s %s\n" "❌ Blocks Missed:" "$blocks_missed"
}

print_slashing_stats() {
    local slashing_stats="$1"
    IFS='|' read -r total_events validator_slashes recent_event <<< "$slashing_stats"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                      SLASHING OVERVIEW                       ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "🚨 Recent Events:" "$total_events"
    printf "%-25s %s\n" "⚠️  Your Validator Hits:" "$validator_slashes"
    printf "%-25s %s\n" "📅 Most Recent Event:" "$recent_event"
    
    if [[ "$validator_slashes" != "0" ]]; then
        warn "⚠️  Your validator has been involved in slashing events!"
    fi
}

print_top_validators() {
    local rank="$1"
    local window_desc="$2"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                     VALIDATOR RANKING                        ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    printf "%-25s %s\n" "📊 Analysis Window:" "$window_desc"
    printf "%-25s %s\n" "🏆 Your Rank:" "$rank"
    
    if [[ "$rank" =~ ^[0-9]+$ ]]; then
        if [[ $rank -le 10 ]]; then
            success "🎉 Excellent! You're in the top 10 validators!"
        elif [[ $rank -le 50 ]]; then
            success "👏 Great performance! You're in the top 50!"
        elif [[ $rank -le 100 ]]; then
            info "👍 Good performance! You're in the top 100!"
        fi
    fi
}

print_accusations() {
    local json_file="$1"
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                        ACCUSATIONS                           ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    
    if [[ ! -f "$json_file" ]] || ! is_valid_json "$json_file"; then
        printf "%-25s %s\n" "📋 Status:" "No data available"
        return
    fi
    
    local total_accusations received_accusations executed_accusations
    
    total_accusations=$(jq -r 'length // 0' "$json_file" 2>/dev/null || echo "0")
    received_accusations=$(jq -r '[.[] | select(.type == "received" or .status == "received")] | length' "$json_file" 2>/dev/null || echo "0")
    executed_accusations=$(jq -r '[.[] | select(.type == "executed" or .status == "executed")] | length' "$json_file" 2>/dev/null || echo "0")
    
    printf "%-25s %s\n" "📋 Total Accusations:" "$total_accusations"
    printf "%-25s %s\n" "📨 Received:" "$received_accusations"
    printf "%-25s %s\n" "⚖️  Executed:" "$executed_accusations"
    
    if [[ "$total_accusations" != "0" ]]; then
        warn "⚠️  Your validator has been accused!"
        
        # Show recent accusations
        local recent_accusations
        recent_accusations=$(jq -r '.[0:3] | .[] | "  • Epoch \(.epoch // .block // "N/A"): \(.type // .reason // "Unknown")"' "$json_file" 2>/dev/null || true)
        
        if [[ -n "$recent_accusations" ]]; then
            echo ""
            echo "Recent accusations:"
            echo "$recent_accusations"
        fi
    fi
}

# Usage and help
usage() {
    cat <<'EOF'
Enhanced Aztec Validator Stats Tool

USAGE:
    aztec-stats <validator_address> [OPTIONS]

VALIDATOR ADDRESS:
    Ethereum address (0x + 40 hex characters)

OPTIONS:
    --epochs START:END      Epoch range for top validators (e.g., 1800:1900)
    --last N                Use last N epochs from current epoch
    --slashing-limit N      Number of recent slashing events to fetch (default: 50)
    --cookie TOKEN          Provide cf_clearance token for this session
    --set-cookie           Interactively set and save cf_clearance token
    --verbose              Show detailed progress information
    --debug                Enable debug output
    --raw                  Show raw API responses on errors
    --help, -h             Show this help message

EXAMPLES:
    # Basic validator stats
    aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3

    # With specific epoch range
    aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --epochs 1797:1897

    # Last 100 epochs with cookie setup
    aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --last 100 --set-cookie

    # Debug mode with verbose output
    aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3 --debug --verbose

FEATURES:
    ✅ Network overview (active/total validators, current epoch)
    ✅ Validator performance (attestations, blocks, balance)
    ✅ Slashing history and your validator's involvement
    ✅ Top validator rankings with your position
    ✅ Accusations received and executed
    ✅ Cloudflare cookie management
    ✅ Comprehensive error handling and logging

DATA SOURCE:
    All data is fetched from dashtec.xyz API
EOF
}

# Main execution
main() {
    local validator_address=""
    local epoch_start=""
    local epoch_end=""
    local last_n=""
    local slashing_limit="50"
    local set_cookie=0
    
    # Parse arguments
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    validator_address="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --epochs)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+:[0-9]+$ ]]; then
                    IFS=':' read -r epoch_start epoch_end <<< "$2"
                    shift 2
                else
                    error "Invalid epochs format. Use: --epochs START:END"
                    exit 1
                fi
                ;;
            --last)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    last_n="$2"
                    shift 2
                else
                    error "Invalid last epochs format. Use: --last N"
                    exit 1
                fi
                ;;
            --slashing-limit)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    slashing_limit="$2"
                    shift 2
                else
                    error "Invalid slashing limit. Use: --slashing-limit N"
                    exit 1
                fi
                ;;
            --cookie)
                CF_CLEARANCE="${2:-}"
                shift 2
                ;;
            --set-cookie)
                set_cookie=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --raw)
                SHOW_RAW=1
                shift
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Initialize
    print_header
    check_dependencies
    load_config
    
    # Handle cookie setup
    if [[ $set_cookie -eq 1 && -z "${CF_CLEARANCE:-}" ]]; then
        prompt_cookie
    fi
    
    # Validate address
    validator_address=$(validate_address "$validator_address")
    
    # Create temporary directory
    tmpdir=$(mktemp -d)
    
    # File paths
    local network_json="$tmpdir/network.json"
    local validator_json="$tmpdir/validator.json"
    local slashing_json="$tmpdir/slashing.json"
    local top_json="$tmpdir/top.json"
    local accusations_json="$tmpdir/accusations.json"
    
    # Fetch network stats
    if fetch_network_stats "$network_json"; then
        network_stats=$(parse_network_stats "$network_json")
        current_epoch=$(echo "$network_stats" | cut -d'|' -f1)
        
        # If we're still getting N/A values in debug mode, show the raw JSON
        if [[ $DEBUG -eq 1 && "$network_stats" == "N/A|N/A|N/A|N/A" ]]; then
            warn "Network stats parsing failed. Raw JSON response:"
            echo "--- NETWORK API RESPONSE ---"
            cat "$network_json" 2>/dev/null || echo "Failed to read response file"
            echo "--- END RESPONSE ---"
        fi
    else
        network_stats="N/A|N/A|N/A|N/A"
        current_epoch=""
    fi
    
    # Fetch validator stats
    if ! fetch_validator_stats "$validator_address" "$validator_json"; then
        cleanup_and_exit 1 "Failed to fetch validator data"
    fi
    validator_stats=$(parse_validator_stats "$validator_json")
    
    # Debug validator parsing if needed
    if [[ $DEBUG -eq 1 ]]; then
        debug "Raw validator stats result: $validator_stats"
        # Show specific parsing issues
        if echo "$validator_stats" | grep -q "N/A.*N/A.*N/A"; then
            warn "Some validator data could not be parsed. Check JSON structure:"
            echo "--- VALIDATOR API RESPONSE (first 500 chars) ---"
            head -c 500 "$validator_json" 2>/dev/null || echo "Failed to read response file"
            echo "--- END PARTIAL RESPONSE ---"
        fi
    fi
    
    # Fetch slashing history
    if fetch_slashing_history "$slashing_json" "$slashing_limit"; then
        slashing_stats=$(parse_slashing_history "$slashing_json" "$validator_address")
    else
        slashing_stats="N/A|0|N/A"
    fi
    
    # Fetch accusations
    if fetch_accusations "$validator_address" "$accusations_json"; then
        accusations_available=1
    else
        accusations_available=0
    fi
    
    # Determine epoch range for top validators
    local window_description="Not specified"
    local validator_rank="N/A"
    
    if [[ -n "$epoch_start" && -n "$epoch_end" ]]; then
        window_description="Epochs ${epoch_start}:${epoch_end}"
        if fetch_top_validators "$top_json" "$epoch_start" "$epoch_end"; then
            validator_rank=$(find_validator_rank "$top_json" "$validator_address")
        fi
    elif [[ -n "$last_n" && -n "$current_epoch" && "$current_epoch" != "N/A" ]]; then
        local start_epoch=$((current_epoch - last_n + 1))
        [[ $start_epoch -lt 0 ]] && start_epoch=0
        window_description="Last ${last_n} epochs (${start_epoch}:${current_epoch})"
        if fetch_top_validators "$top_json" "$start_epoch" "$current_epoch"; then
            validator_rank=$(find_validator_rank "$top_json" "$validator_address")
        fi
    elif [[ -n "$current_epoch" && "$current_epoch" != "N/A" ]]; then
        # Default to last 50 epochs if we have current epoch but no specific range
        local default_range=50
        local start_epoch=$((current_epoch - default_range + 1))
        [[ $start_epoch -lt 0 ]] && start_epoch=0
        window_description="Auto: Last ${default_range} epochs (${start_epoch}:${current_epoch})"
        info "No epoch range specified, using default last $default_range epochs"
        if fetch_top_validators "$top_json" "$start_epoch" "$current_epoch"; then
            validator_rank=$(find_validator_rank "$top_json" "$validator_address")
        fi
    else
        warn "Cannot determine epoch range - current epoch unknown. Use --epochs START:END or --last N"
        window_description="Cannot determine (no current epoch)"
    fi
    
    # Display results
    print_network_stats "$network_stats"
    print_validator_stats "$validator_address" "$validator_stats"
    print_slashing_stats "$slashing_stats"
    print_top_validators "$validator_rank" "$window_description"
    
    if [[ $accusations_available -eq 1 ]]; then
        print_accusations "$accusations_json"
    else
        echo ""
        highlight "╔══════════════════════════════════════════════════════════════╗"
        highlight "║                        ACCUSATIONS                           ║"
        highlight "╚══════════════════════════════════════════════════════════════╝"
        printf "%-25s %s\n" "📋 Status:" "No accusations data available"
    fi
    
    # Summary footer
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                         SUMMARY                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    success "✅ Data successfully retrieved from dashtec.xyz"
    info "🕒 Generated on: $(date)"
    
    # Debug information
    if [[ $DEBUG -eq 1 ]]; then
        echo ""
        echo "🔍 DEBUG INFORMATION:"
        echo "  Network data: $network_json"
        echo "  Validator data: $validator_json"
        echo "  Slashing data: $slashing_json"
        [[ -f "$top_json" ]] && echo "  Top validators: $top_json"
        [[ -f "$accusations_json" ]] && echo "  Accusations: $accusations_json"
        echo "  Config file: $CONFIG_FILE"
        echo "  Cache directory: $CACHE_DIR"
    fi
    
    # Cleanup
    cleanup_and_exit 0
}

# Execute main function with all arguments
main "$@"
