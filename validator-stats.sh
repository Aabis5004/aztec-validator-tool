#!/bin/bash

# Aztec Validator Stats Tool - WSL Optimized
# Author: Aabis Lone

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# WSL-specific dependency check
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_warning "Installing missing dependencies: ${missing_deps[*]}"
        print_info "This requires sudo access..."
        
        # Update package list first
        sudo apt update
        
        # Install missing dependencies
        sudo apt install -y "${missing_deps[@]}"
        
        print_success "Dependencies installed successfully!"
    fi
}

main() {
    # Clear screen and show header
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  AZTEC VALIDATOR STATS TOOL                 ║"
    echo "║                     WSL Edition                              ║"
    echo "║                     by Aabis Lone                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check arguments
    if [ $# -eq 0 ]; then
        print_error "Usage: $0 <validator_address>"
        print_info "Example: $0 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
        echo ""
        print_info "This tool fetches:"
        echo "  • Total attestations and success rate"
        echo "  • Block proposals and mining stats"
        echo "  • Performance analysis with ratings"
        exit 1
    fi

    VALIDATOR_ADDR="$1"

    # Validate address
    if [[ ! "$VALIDATOR_ADDR" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid validator address format!"
        print_info "Must be: 0x + 40 hexadecimal characters"
        exit 1
    fi

    # Install dependencies if needed
    check_dependencies

    print_info "Fetching validator stats for: $VALIDATOR_ADDR"
    echo ""

    # API call
    API_URL="https://dashtec.xyz/api/validators/${VALIDATOR_ADDR}"
    TEMP_FILE=$(mktemp)

    # Fetch data with timeout
    if ! timeout 30 curl -s \
         -H "Accept: application/json" \
         -H "User-Agent: Mozilla/5.0 (WSL; Aztec Validator Tool)" \
         "$API_URL" -o "$TEMP_FILE"; then
        print_error "Failed to fetch data from API"
        print_info "Check your internet connection"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # Validate JSON response
    if ! jq empty "$TEMP_FILE" 2>/dev/null; then
        print_error "Invalid API response"
        print_warning "This might be due to:"
        echo "  • Rate limiting"
        echo "  • Invalid validator address"
        echo "  • API server issues"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    # Parse JSON data
    ADDRESS=$(jq -r '.address // "N/A"' "$TEMP_FILE")
    STATUS=$(jq -r '.status // "N/A"' "$TEMP_FILE")
    ATTESTATION_SUCCESS=$(jq -r '.attestationSuccess // "N/A"' "$TEMP_FILE")
    ATTESTATIONS_SUCCEEDED=$(jq -r '.totalAttestationsSucceeded // 0' "$TEMP_FILE")
    ATTESTATIONS_MISSED=$(jq -r '.totalAttestationsMissed // 0' "$TEMP_FILE")
    BLOCKS_PROPOSED=$(jq -r '.totalBlocksProposed // 0' "$TEMP_FILE")
    BLOCKS_MINED=$(jq -r '.totalBlocksMined // 0' "$TEMP_FILE")
    BLOCKS_MISSED=$(jq -r '.totalBlocksMissed // 0' "$TEMP_FILE")

    TOTAL_ATTESTATIONS=$((ATTESTATIONS_SUCCEEDED + ATTESTATIONS_MISSED))

    # Display comprehensive stats
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                        VALIDATOR INFO                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-20s %s\n" "Address:" "$ADDRESS"
    printf "%-20s %s\n" "Status:" "$STATUS"
    printf "%-20s %s\n" "Success Rate:" "$ATTESTATION_SUCCESS"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      ATTESTATION STATS                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-20s %s\n" "Total Attestations:" "$TOTAL_ATTESTATIONS"
    printf "%-20s %s\n" "  └─ Succeeded:" "$ATTESTATIONS_SUCCEEDED"
    printf "%-20s %s\n" "  └─ Missed:" "$ATTESTATIONS_MISSED"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                        BLOCK STATS                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-20s %s\n" "Blocks Proposed:" "$BLOCKS_PROPOSED"
    printf "%-20s %s\n" "Blocks Mined:" "$BLOCKS_MINED"
    printf "%-20s %s\n" "Blocks Missed:" "$BLOCKS_MISSED"

    # Performance Analysis
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    PERFORMANCE ANALYSIS                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$TOTAL_ATTESTATIONS" -gt 0 ]]; then
        SUCCESS_RATE=$(echo "scale=1; $ATTESTATIONS_SUCCEEDED * 100 / $TOTAL_ATTESTATIONS" | bc)
        printf "Attestation Success: %.1f%% (%d/%d)\n" "$SUCCESS_RATE" "$ATTESTATIONS_SUCCEEDED" "$TOTAL_ATTESTATIONS"
        
        # Performance rating with emojis
        if (( $(echo "$SUCCESS_RATE >= 99" | bc -l) )); then
            echo "Rating: 🟢 EXCELLENT - Top performer!"
        elif (( $(echo "$SUCCESS_RATE >= 95" | bc -l) )); then
            echo "Rating: 🟡 GOOD - Solid performance"
        elif (( $(echo "$SUCCESS_RATE >= 90" | bc -l) )); then
            echo "Rating: 🟠 FAIR - Room for improvement"
        else
            echo "Rating: 🔴 NEEDS IMPROVEMENT - Check validator setup"
        fi
    else
        echo "No attestation data available yet"
    fi

    if [[ "$BLOCKS_PROPOSED" -gt 0 ]]; then
        BLOCK_RATE=$(echo "scale=1; $BLOCKS_MINED * 100 / $BLOCKS_PROPOSED" | bc)
        printf "Block Success: %.1f%% (%d/%d)\n" "$BLOCK_RATE" "$BLOCKS_MINED" "$BLOCKS_PROPOSED"
    fi

    echo ""
    echo "╚══════════════════════════════════════════════════════════════╝"

    # Cleanup
    rm -f "$TEMP_FILE"
    
    echo ""
    print_success "Stats retrieved successfully!"
    print_info "Data source: dashtec.xyz API"
    echo ""
}

# Run main function
main "$@"
