#!/bin/bash
# Aztec Validator Stats Tool - WSL/Linux/macOS
# Author: Aabis Lone

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ${NC} $*"; }
ok(){ echo -e "${GREEN}✓${NC} $*"; }
err(){ echo -e "${RED}✗${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*"; }

is_wsl(){ grep -qi microsoft /proc/version 2>/dev/null; }
need(){ command -v "$1" >/dev/null 2>&1; }

install_missing() {
  local missing=()
  for c in curl jq bc timeout; do need "$c" || missing+=("$c"); done
  ((${#missing[@]}==0)) && return 0
  warn "Installing missing dependencies: ${missing[*]}"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if need brew; then brew install curl jq bc coreutils; else err "Install Homebrew: https://brew.sh"; exit 1; fi
  else
    info "Updating apt and installing… (requires sudo)"
    sudo apt update
    sudo apt install -y curl jq bc coreutils ca-certificates
    sudo update-ca-certificates || true
  fi
  ok "Dependencies installed."
}

print_header() {
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                  AZTEC VALIDATOR STATS TOOL                 ║"
  echo "║                        WSL Edition                           ║"
  echo "║                        by Aabis Lone                         ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
}

usage() {
  err "Usage: $(basename "$0") <validator_address>  [--debug|-d]"
  info "Example: $(basename "$0") 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
  echo
  info "This tool fetches:"
  echo "  • Total attestations and success rate"
  echo "  • Block proposals and mining stats"
  echo "  • Performance analysis with ratings"
}

main() {
  clear || true
  print_header

  # Parse args
  DEBUG=0
  VAL_ADDR="${1:-}"
  if [[ "${2:-}" == "--debug" || "${2:-}" == "-d" ]]; then DEBUG=1; fi

  # Prompt if no address provided
  if [[ -z "$VAL_ADDR" ]]; then
    read -r -p "Enter your validator address (0x…40 hex): " VAL_ADDR
  fi

  # Validate address
  if [[ ! "$VAL_ADDR" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    err "Invalid validator address format!"
    info "Must be: 0x + 40 hexadecimal characters"
    echo
    usage
    exit 1
  fi

  install_missing

  info "Fetching validator stats for: $VAL_ADDR"
  echo

  API_URL="https://dashtec.xyz/api/validators/${VAL_ADDR}"
  TMP_JSON="$(mktemp)"

  # Fetch with explicit status code
  HTTP_CODE=$(curl -sS -w "%{http_code}" \
    -H "Accept: application/json" \
    -H "User-Agent: Aztec-Validator-Stats (WSL)" \
    --max-time 30 \
    "$API_URL" -o "$TMP_JSON") || HTTP_CODE="000"

  if [[ "$HTTP_CODE" != "200" ]]; then
    err "API request failed (HTTP $HTTP_CODE)"
    warn "URL: $API_URL"
    if [[ "$HTTP_CODE" == "404" ]]; then
      warn "Validator not found. Check the address."
    elif [[ "$HTTP_CODE" == "000" ]]; then
      warn "Network error or timeout. Check your internet/WSL DNS."
    fi
    [[ -s "$TMP_JSON" ]] && echo -e "\nResponse body:\n$(head -c 400 "$TMP_JSON")"
    rm -f "$TMP_JSON"
    exit 1
  fi

  # Validate JSON
  if ! jq -e type >/dev/null 2>&1 <"$TMP_JSON"; then
    err "Invalid JSON response from API."
    [[ -s "$TMP_JSON" ]] && echo -e "\nResponse body:\n$(head -c 400 "$TMP_JSON")"
    rm -f "$TMP_JSON"
    exit 1
  fi

  (( DEBUG )) && { echo "----- RAW JSON (debug) -----"; cat "$TMP_JSON"; echo; }

  # Extract fields with sane defaults
  ADDRESS=$(jq -r '.address // "N/A"' "$TMP_JSON")
  STATUS=$(jq -r '.status // "N/A"' "$TMP_JSON")
  ATTESTATION_SUCCESS=$(jq -r '.attestationSuccess // "N/A"' "$TMP_JSON")
  SUCC=$(jq -r '.totalAttestationsSucceeded // 0' "$TMP_JSON")
  MISS=$(jq -r '.totalAttestationsMissed // 0' "$TMP_JSON")
  PROP=$(jq -r '.totalBlocksProposed // 0' "$TMP_JSON")
  MINED=$(jq -r '.totalBlocksMined // 0' "$TMP_JSON")
  BMISS=$(jq -r '.totalBlocksMissed // 0' "$TMP_JSON")

  TOTAL=$(( SUCC + MISS ))

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                        VALIDATOR INFO                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  printf "%-20s %s\n" "Address:" "$ADDRESS"
  printf "%-20s %s\n" "Status:" "$STATUS"
  printf "%-20s %s\n" "Success Rate:" "$ATTESTATION_SUCCESS"
  echo

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                      ATTESTATION STATS                      ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  printf "%-20s %s\n" "Total Attestations:" "$TOTAL"
  printf "%-20s %s\n" "  └─ Succeeded:" "$SUCC"
  printf "%-20s %s\n" "  └─ Missed:" "$MISS"
  echo

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                          BLOCK STATS                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  printf "%-20s %s\n" "Blocks Proposed:" "$PROP"
  printf "%-20s %s\n" "Blocks Mined:" "$MINED"
  printf "%-20s %s\n" "Blocks Missed:" "$BMISS"
  echo

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    PERFORMANCE ANALYSIS                     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  if (( TOTAL > 0 )); then
    # Use awk to avoid bc float quirks when missing scale
    SUCCESS_RATE=$(awk -v s="$SUCC" -v t="$TOTAL" 'BEGIN{ if(t>0){ printf "%.1f", (s*100.0)/t } else { print "0.0" } }')
    printf "Attestation Success: %s%% (%d/%d)\n" "$SUCCESS_RATE" "$SUCC" "$TOTAL"
    SR_INT=$(printf "%.0f" "$SUCCESS_RATE")
    if (( SR_INT >= 99 )); then
      echo "Rating: 🟢 EXCELLENT - Top performer!"
    elif (( SR_INT >= 95 )); then
      echo "Rating: 🟡 GOOD - Solid performance"
    elif (( SR_INT >= 90 )); then
      echo "Rating: 🟠 FAIR - Room for improvement"
    else
      echo "Rating: 🔴 NEEDS IMPROVEMENT - Check validator setup"
    fi
  else
    echo "No attestation data available yet."
  fi

  if (( PROP > 0 )); then
    BLOCK_RATE=$(awk -v m="$MINED" -v p="$PROP" 'BEGIN{ if(p>0){ printf "%.1f", (m*100.0)/p } else { print "0.0" } }')
    printf "Block Success: %s%% (%d/%d)\n" "$BLOCK_RATE" "$MINED" "$PROP"
  fi

  echo
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  ok "Stats retrieved successfully!"
  info "Data source: dashtec.xyz API"
  echo

  rm -f "$TMP_JSON"
}

main "$@"
