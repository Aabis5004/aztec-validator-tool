#!/usr/bin/env bash
# Aztec Validator Stats – Extended (WSL/Mac/Linux)
# Author: Aabis Lone

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ${NC} $*"; }
ok(){ echo -e "${GREEN}✓${NC} $*"; }
err(){ echo -e "${RED}✗${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*"; }

CONFIG_FILE="${HOME}/.aztec-validator-tool.conf"
INSTALL_DIR="${HOME}/aztec-validator-tool"
UA_DEFAULT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"

DASHTEC_HOST="https://dashtec.xyz"
API_VALIDATOR="${DASHTEC_HOST}/api/validators"
API_GENERAL="${DASHTEC_HOST}/api/stats/general"
API_SLASHING="${DASHTEC_HOST}/api/slashing-history"
API_TOP="${DASHTEC_HOST}/api/dashboard/top-validators"

CF_CLEARANCE="${CF_CLEARANCE:-}"
USER_AGENT="${USER_AGENT:-$UA_DEFAULT}"
REFERER="https://dashtec.xyz/"

trap 'err "Unexpected error. Try with --debug"; exit 1' ERR

detect_os() {
  if [[ "${OSTYPE:-}" == linux-gnu* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi
  elif [[ "${OSTYPE:-}" == darwin* ]]; then OS="mac"; else OS="unknown"; fi
}

install_deps() {
  local missing=()
  for b in curl jq bc; do command -v "$b" >/dev/null 2>&1 || missing+=("$b"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  warn "Installing missing dependencies: ${missing[*]}"
  case "${OS}" in
    wsl|linux) sudo apt update && sudo apt install -y "${missing[@]}" ;;
    mac) command -v brew >/dev/null || { err "Install Homebrew: https://brew.sh"; exit 1; }; brew install "${missing[@]}" ;;
    *) err "Unsupported OS: ${OSTYPE:-unknown}"; exit 1 ;;
  esac
  ok "Dependencies installed"
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || true
  # env var beats config
  if [[ -n "${CF_CLEARANCE:-}" ]]; then
    CF_CLEARANCE="$CF_CLEARANCE"
  else
    CF_CLEARANCE="${CF_CLEARANCE_CONFIG:-${CF_CLEARANCE:-}}"
  fi
}

save_cookie() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  # shellcheck disable=SC2016
  cat > "$CONFIG_FILE" <<EOF
# Saved by aztec-stats
CF_CLEARANCE_CONFIG='${CF_CLEARANCE}'
USER_AGENT='${USER_AGENT}'
EOF
  ok "Saved cookie to $CONFIG_FILE"
}

prompt_cookie() {
  read -r -p "Paste cf_clearance (empty to skip): " CF_INPUT || true
  if [[ -n "${CF_INPUT:-}" ]]; then
    CF_CLEARANCE="$CF_INPUT"
    save_cookie
  else
    warn "Continuing without cf_clearance (may fail if Cloudflare blocks requests)"
  fi
}

usage() {
  cat <<'EOU'
Usage:
  aztec-stats <validator_address> [options]

Options:
  --epochs START:END    Epoch window for Top Validators (e.g., 1800:1899)
  --last N              Use last N epochs ending at current epoch (if available)
  --cookie TOKEN        Provide Cloudflare cf_clearance token for this run
  --set-cookie          Prompt once and save cf_clearance for future runs
  --debug               Print raw JSON snippets for troubleshooting
  -h, --help            Show help

Examples:
  aztec-stats 0x581f8a...e3
  aztec-stats 0x581f8a...e3 --epochs 1797:1897
  aztec-stats 0x581f8a...e3 --last 120 --set-cookie
EOU
}

# Robust GET that writes body to a temp file and echoes HTTP code
http_get() {
  local url="$1"; local out="$2"; shift 2
  local -a curl_args=(-sSL -H "User-Agent: ${USER_AGENT}" -H "Accept: */*" -H "Referer: ${REFERER}")
  [[ -n "${CF_CLEARANCE:-}" ]] && curl_args+=(-H "Cookie: cf_clearance=${CF_CLEARANCE}")
  local code
  code=$(curl "${curl_args[@]}" -w '%{http_code}' -o "$out" "$url" || true)
  echo "$code"
}

# Pretty JSON guard
is_json() { jq -e . >/dev/null 2>&1 < "$1"; }

# ---- Parse flags
ADDR="${1:-}"
[[ -z "${ADDR}" || "${ADDR}" == "-h" || "${ADDR}" == "--help" ]] && { usage; exit 1; }
shift || true

EPOCH_START=""; EPOCH_END=""; LAST_N=""; DEBUG=0; SET_COOKIE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --epochs) IFS=':' read -r EPOCH_START EPOCH_END <<< "${2:-}"; shift 2 ;;
    --last) LAST_N="${2:-}"; shift 2 ;;
    --cookie) CF_CLEARANCE="${2:-}"; shift 2 ;;
    --set-cookie) SET_COOKIE=1; shift ;;
    --debug) DEBUG=1; shift ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# ---- Bootstrap
clear || true
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               AZTEC VALIDATOR STATS – EXTENDED               ║"
echo "║                        by Aabis Lone                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

detect_os
install_deps
load_config
[[ $SET_COOKIE -eq 1 && -z "${CF_CLEARANCE:-}" ]] && prompt_cookie

# Lowercase and validate address
ADDR_LC="$(echo "$ADDR" | tr 'A-F' 'a-f')"
if [[ ! "$ADDR_LC" =~ ^0x[0-9a-f]{40}$ ]]; then
  err "Invalid address format. Must be 0x + 40 hex chars"
  exit 1
fi

tmpdir="$(mktemp -d)"
cleanup(){ rm -rf "$tmpdir"; }
trap cleanup EXIT

# ---- 1) General network stats
info "Fetching network stats…"
GEN_JSON="$tmpdir/general.json"
code=$(http_get "${API_GENERAL}" "$GEN_JSON")
if [[ "$code" == "200" && -s "$GEN_JSON" && $(is_json "$GEN_JSON"; echo $?) -eq 0 ]]; then
  CURRENT_EPOCH="$(jq -r '.currentEpoch // .epoch // .latestEpoch // empty' "$GEN_JSON")"
  ACTIVE_V="$(jq -r '.activeValidators // .validators.active // .active // empty' "$GEN_JSON")"
  TOTAL_V="$(jq -r '.totalValidators // .validators.total // .total // empty' "$GEN_JSON")"
else
  warn "Could not read general stats (HTTP $code)."
  CURRENT_EPOCH=""; ACTIVE_V=""; TOTAL_V=""
fi

# ---- 2) Your validator stats
info "Fetching validator stats for: $ADDR_LC"
VAL_JSON="$tmpdir/validator.json"
code=$(http_get "${API_VALIDATOR}/${ADDR_LC}" "$VAL_JSON")
if [[ "$code" != "200" || ! -s "$VAL_JSON" || $(is_json "$VAL_JSON"; echo $?) -ne 0 ]]; then
  err "Failed to fetch validator details (HTTP $code)."
  [[ $DEBUG -eq 1 ]] && { echo "--- RAW ---"; cat "$VAL_JSON" 2>/dev/null || true; }
  exit 1
fi

V_STATUS="$(jq -r '.status // "N/A"' "$VAL_JSON")"
AT_SUCC="$(jq -r '.totalAttestationsSucceeded // 0' "$VAL_JSON")"
AT_MISS="$(jq -r '.totalAttestationsMissed // 0' "$VAL_JSON")"
AT_SUCCESS_RATE="$(jq -r '.attestationSuccess // empty' "$VAL_JSON")"
BLK_PROP="$(jq -r '.totalBlocksProposed // 0' "$VAL_JSON")"
BLK_MINED="$(jq -r '.totalBlocksMined // 0' "$VAL_JSON")"
BLK_MISS="$(jq -r '.totalBlocksMissed // 0' "$VAL_JSON")"
AT_TOTAL=$(( AT_SUCC + AT_MISS ))

# ---- 3) Slashing history (global last 10; show matches for your address if present)
info "Fetching recent slashing history…"
SLASH_JSON="$tmpdir/slashing.json"
code=$(http_get "${API_SLASHING}?page=1&limit=10" "$SLASH_JSON")
SLASH_COUNT="N/A"; SLASH_MY_COUNT=0
if [[ "$code" == "200" && -s "$SLASH_JSON" && $(is_json "$SLASH_JSON"; echo $?) -eq 0 ]]; then
  # array or {data:[…]}
  SLASH_COUNT="$(jq -r 'if type=="array" then length else (.data|length // 0) end' "$SLASH_JSON")"
  SLASH_MY_COUNT="$(jq -r --arg addr "$ADDR_LC" '
     (if has("data") then .data else . end)
     | if type=="array" then
         [ .[] | ( .validator // .address // .pubkey // "" ) | ascii_downcase | select(. == $addr) ] | length
       else 0 end
  ' "$SLASH_JSON")"
else
  warn "Slashing endpoint not available (HTTP $code)."
fi

# ---- 4) Top validators (epoch window)
TOP_NOTE="(skipped)"
TOP_JSON="$tmpdir/top.json"
if [[ -n "${EPOCH_START:-}" && -n "${EPOCH_END:-}" ]]; then
  info "Fetching Top Validators for epochs ${EPOCH_START}:${EPOCH_END}…"
  code=$(http_get "${API_TOP}?startEpoch=${EPOCH_START}&endEpoch=${EPOCH_END}" "$TOP_JSON")
  TOP_NOTE="epochs ${EPOCH_START}:${EPOCH_END}"
elif [[ -n "${LAST_N:-}" && -n "${CURRENT_EPOCH:-}" ]]; then
  START=$(( CURRENT_EPOCH - LAST_N + 1 )); END=$(( CURRENT_EPOCH ))
  [[ $START -lt 0 ]] && START=0
  info "Fetching Top Validators for last ${LAST_N} epochs (${START}:${END})…"
  code=$(http_get "${API_TOP}?startEpoch=${START}&endEpoch=${END}" "$TOP_JSON")
  TOP_NOTE="last ${LAST_N} (=${START}:${END})"
else
  warn "Top Validators: no epoch window provided (use --epochs START:END or --last N)."
  code=""; TOP_NOTE="(no epoch window)"
fi

MY_RANK="N/A"
if [[ "$code" == "200" && -s "$TOP_JSON" && $(is_json "$TOP_JSON"; echo $?) -eq 0 ]]; then
  # Find a row whose any id-like field matches address
  MY_RANK="$(jq -r --arg addr "$ADDR_LC" '
    def norm: tostring | ascii_downcase;
    def as_list: if type=="array" then . else .data // [] end;
    as_list
    | to_entries
    | map( . + {match:
        (
          .value.address? // .value.validator? // .value.pubkey? // ""
        ) | norm == ($addr | norm)
      })
    | map(select(.match))
    | (.[0].key + 1) // empty
  ' "$TOP_JSON" 2>/dev/null || echo "")"
  [[ -z "$MY_RANK" ]] && MY_RANK="Not in window"
fi

# ---- Output
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                        NETWORK STATS                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Active Validators:" "${ACTIVE_V:-N/A}"
printf "%-20s %s\n" "Total Validators:"  "${TOTAL_V:-N/A}"
printf "%-20s %s\n" "Current Epoch:"     "${CURRENT_EPOCH:-N/A}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                        VALIDATOR INFO                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Address:" "$ADDR_LC"
printf "%-20s %s\n" "Status:"  "$V_STATUS"
printf "%-20s %s\n" "Success Rate:" "${AT_SUCCESS_RATE:-N/A}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      ATTESTATION STATS                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Total:"   "$AT_TOTAL"
printf "%-20s %s\n" "  └─ Succeeded:" "$AT_SUCC"
printf "%-20s %s\n" "  └─ Missed:"    "$AT_MISS"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                          BLOCK STATS                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Proposed:" "$BLK_PROP"
printf "%-20s %s\n" "Mined:"    "$BLK_MINED"
printf "%-20s %s\n" "Missed:"   "$BLK_MISS"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                       SLASHING HISTORY                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Recent events (10):" "$SLASH_COUNT"
printf "%-20s %s\n" "Your validator hits:" "$SLASH_MY_COUNT"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                         TOP VALIDATORS                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "%-20s %s\n" "Window:" "$TOP_NOTE"
printf "%-20s %s\n" "Your rank:" "$MY_RANK"

echo ""
echo "╚══════════════════════════════════════════════════════════════╝"
ok "Stats retrieved."
info "Data source: dashtec.xyz API"
[[ $DEBUG -eq 1 ]] && { echo -e "\n--- DEBUG paths ---"; echo "general: $GEN_JSON"; echo "validator: $VAL_JSON"; echo "slashing: $SLASH_JSON"; [[ -s "$TOP_JSON" ]] && echo "top: $TOP_JSON" || true; }
