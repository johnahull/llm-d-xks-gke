#!/bin/bash
#
# Enhanced TPU availability checker for Google Cloud
#
# Usage:
#   ./check-tpu-availability-enhanced.sh [options] [project-id]
#
# Options:
#   -f, --filter <gen>    Filter by TPU generation (v2, v3, v4, v5, v5e, v5p, v6e)
#   -s, --single-chip     Only show single-chip TPUs (v6e-1, v5litepod-1, etc.)
#   -r, --region <region> Only check zones in specific region (e.g., us-central1)
#   -h, --help            Show this help message
#
# Examples:
#   ./check-tpu-availability-enhanced.sh -f v6e ecoeng-llmd
#   ./check-tpu-availability-enhanced.sh -s -r us-east5 ecoeng-llmd
#   ./check-tpu-availability-enhanced.sh --filter v5p

set -euo pipefail

# Parse arguments
FILTER=""
SINGLE_CHIP=false
REGION_FILTER=""
PROJECT=""

show_help() {
    grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -s|--single-chip)
            SINGLE_CHIP=true
            shift
            ;;
        -r|--region)
            REGION_FILTER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            ;;
        *)
            PROJECT="$1"
            shift
            ;;
    esac
done

# Set project
if [ -z "$PROJECT" ]; then
    PROJECT=$(gcloud config get-value project 2>/dev/null || echo '')
fi

if [ -z "$PROJECT" ]; then
    echo "Error: No project specified and no default project configured"
    echo "Usage: $0 [options] [project-id]"
    exit 1
fi

echo "Checking TPU availability for project: $PROJECT"
if [ -n "$FILTER" ]; then
    echo "Filter: TPU generation $FILTER"
fi
if [ "$SINGLE_CHIP" = true ]; then
    echo "Filter: Single-chip TPUs only"
fi
if [ -n "$REGION_FILTER" ]; then
    echo "Filter: Region $REGION_FILTER"
fi
echo "=========================================="
echo ""

# Known TPU zones
TPU_ZONES=(
    "us-central1-a"
    "us-central1-b"
    "us-central1-c"
    "us-central1-f"
    "us-central2-b"
    "us-east1-c"
    "us-east1-d"
    "us-east5-a"
    "us-east5-b"
    "us-east5-c"
    "us-south1-a"
    "us-south1-b"
    "us-west1-a"
    "us-west1-b"
    "us-west4-a"
    "europe-west4-a"
    "europe-west4-b"
    "asia-east1-c"
    "asia-northeast1-a"
    "asia-southeast1-c"
)

# Filter zones by region if specified
if [ -n "$REGION_FILTER" ]; then
    FILTERED_ZONES=()
    for zone in "${TPU_ZONES[@]}"; do
        if [[ "$zone" == "$REGION_FILTER"* ]]; then
            FILTERED_ZONES+=("$zone")
        fi
    done
    TPU_ZONES=("${FILTERED_ZONES[@]}")
fi

# Function to check TPU types in a zone
check_zone() {
    local zone=$1
    local result=$(gcloud compute tpus accelerator-types list \
        --zone="$zone" \
        --project="$PROJECT" \
        --format="value(name)" \
        2>/dev/null || echo "")

    if [ -z "$result" ]; then
        return
    fi

    # Extract just the TPU type (last part of the path)
    local types=$(echo "$result" | sed 's|.*/||')

    # Apply filters
    if [ -n "$FILTER" ]; then
        types=$(echo "$types" | grep "^$FILTER" || true)
    fi

    if [ "$SINGLE_CHIP" = true ]; then
        types=$(echo "$types" | grep -E '(-1$|-1-)' || true)
    fi

    if [ -n "$types" ]; then
        echo "✓ $zone"
        echo "$types" | sort -V | sed 's/^/    /'
        echo ""
    fi
}

export -f check_zone
export PROJECT FILTER SINGLE_CHIP

echo "Scanning zones..."
echo ""

# Group results by TPU generation
declare -A tpu_by_gen

for zone in "${TPU_ZONES[@]}"; do
    check_zone "$zone"
done

echo "=========================================="
echo "Scan complete!"
echo ""
echo "Common single-chip TPU types:"
echo "  v6e-1     - TPU v6e (cost-effective, latest gen)"
echo "  v5e-1     - TPU v5e"
echo "  v4-8      - TPU v4 (8 chips)"
echo "  v3-8      - TPU v3 (8 chips)"
echo "  v2-8      - TPU v2 (8 chips)"
echo ""
echo "To create a TPU VM:"
echo "  gcloud compute tpus tpu-vm create <name> \\"
echo "    --zone=<zone> \\"
echo "    --accelerator-type=<type> \\"
echo "    --version=v2-alpha-tpuv6e \\"  # For v6e
echo "    --project=$PROJECT"
