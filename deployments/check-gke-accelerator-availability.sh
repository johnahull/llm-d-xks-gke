#!/bin/bash
# Check GKE TPU and GPU availability in zones
# This script validates that accelerators are supported in GKE

set -e

PROJECT=${PROJECT:-ecoeng-llmd}
USE_API=false
SHOW_MACHINE_TYPES=false

# ============================================================================
# API Data Fetching Functions
# ============================================================================

get_zone_region_name() {
    local zone="$1"
    # Extract region from zone (e.g., us-central1-a -> us-central1)
    local region="${zone%-*}"

    # Map regions to friendly names
    case "$region" in
        us-central1) echo "US Central" ;;
        us-east1) echo "US East" ;;
        us-east4) echo "US East (Virginia)" ;;
        us-east5) echo "US East (Columbus)" ;;
        us-south1) echo "US South (Dallas)" ;;
        us-west1) echo "US West (Oregon)" ;;
        us-west2) echo "US West (Los Angeles)" ;;
        us-west4) echo "US West (Las Vegas)" ;;
        europe-west1) echo "Europe (Belgium)" ;;
        europe-west4) echo "Europe (Netherlands)" ;;
        asia-east1) echo "Asia (Taiwan)" ;;
        asia-southeast1) echo "Asia (Singapore)" ;;
        asia-northeast1) echo "Asia (Tokyo)" ;;
        southamerica-west1) echo "South America (Santiago)" ;;
        *) echo "$region" ;;
    esac
}

fetch_gpu_zones_from_api() {
    local accelerator_type="$1"
    local array_name="$2"

    echo "  Fetching $accelerator_type zones from API..." >&2

    # Query gcloud for accelerator availability
    local zones
    zones=$(gcloud compute accelerator-types list \
        --filter="name:$accelerator_type" \
        --format="value(zone)" \
        --project="$PROJECT" 2>/dev/null | sort -u)

    if [[ -z "$zones" ]]; then
        echo "  Warning: No zones found for $accelerator_type" >&2
        return 1
    fi

    # Dynamically build the associative array
    local -n target_array=$array_name
    while IFS= read -r zone; do
        local region_name=$(get_zone_region_name "$zone")
        # Mark us-central1-a for T4 as currently used
        if [[ "$zone" == "us-central1-a" && "$accelerator_type" == "nvidia-tesla-t4" ]]; then
            target_array["$zone"]="$region_name ⭐"
        else
            target_array["$zone"]="$region_name"
        fi
    done <<< "$zones"

    echo "  Found ${#target_array[@]} zones for $accelerator_type" >&2
}

fetch_tpu_zones_from_api() {
    local tpu_version="$1"
    local array_name="$2"

    echo "  Fetching TPU $tpu_version zones from API..." >&2

    # Query gcloud for TPU accelerator availability
    local zones
    zones=$(gcloud compute accelerator-types list \
        --filter="name:$tpu_version" \
        --format="value(zone)" \
        --project="$PROJECT" 2>/dev/null | sort -u)

    if [[ -z "$zones" ]]; then
        echo "  Warning: No zones found for TPU $tpu_version" >&2
        return 1
    fi

    # Dynamically build the associative array
    local -n target_array=$array_name
    while IFS= read -r zone; do
        local region_name=$(get_zone_region_name "$zone")
        target_array["$zone"]="$region_name"
    done <<< "$zones"

    echo "  Found ${#target_array[@]} zones for TPU $tpu_version" >&2
}

load_api_data() {
    echo "=========================================" >&2
    echo "Fetching live data from Google Cloud API" >&2
    echo "=========================================" >&2
    echo "This may take 10-20 seconds..." >&2
    echo "" >&2

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo "Error: Not authenticated to gcloud. Run: gcloud auth login" >&2
        exit 1
    fi

    # Fetch GPU data
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "gpu" ]]; then
        fetch_gpu_zones_from_api "nvidia-tesla-t4" "GPU_T4_ZONES" || true
        fetch_gpu_zones_from_api "nvidia-tesla-a100" "GPU_A100_ZONES" || true
        fetch_gpu_zones_from_api "nvidia-l4" "GPU_L4_ZONES" || true
        fetch_gpu_zones_from_api "nvidia-h100-80gb" "GPU_H100_ZONES" || true
    fi

    # Fetch TPU data
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "tpu" ]]; then
        fetch_tpu_zones_from_api "tpu-v6e-slice" "TPU_V6E_ZONES" || true
        fetch_tpu_zones_from_api "tpu-v5e" "TPU_V5E_ZONES" || true
        fetch_tpu_zones_from_api "tpu-v5p-slice" "TPU_V5P_ZONES" || true
    fi

    echo "" >&2
    echo "API data fetch complete" >&2
    echo "=========================================" >&2
    echo "" >&2
}

fetch_and_display_machine_types() {
    echo "========================================="
    echo "Available Machine Types from API"
    echo "========================================="
    echo "Fetching machine types (this may take 10-15 seconds)..."
    echo ""

    # Determine which zones to query based on filters
    local zones_to_query=()

    if [[ -n "$REGION_FILTER" ]]; then
        # Query specific region zones
        if [[ "$REGION_FILTER" == *"*"* ]]; then
            # Wildcard pattern - query a few common zones
            zones_to_query=("us-central1-a" "us-east1-c" "us-west1-a" "europe-west4-a")
        else
            # Specific region - query one zone from that region
            zones_to_query=("${REGION_FILTER}-a")
        fi
    else
        # Default: query representative zones
        zones_to_query=("us-central1-a" "us-east4-a")
    fi

    # Fetch TPU machine types
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "tpu" ]]; then
        echo "TPU Machine Types:"
        echo "----------------------------------------"

        for zone in "${zones_to_query[@]}"; do
            echo "Zone: $zone"
            gcloud compute machine-types list \
                --zones="$zone" \
                --filter="name:ct6e OR name:ct5e OR name:ct5p" \
                --format="table[box](name,guestCpus,memoryMb.yesno(no='',yes=size()),description)" \
                --project="$PROJECT" 2>/dev/null | head -20
            echo ""
            break  # Only show one zone for TPUs
        done
    fi

    # Fetch GPU machine types
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "gpu" ]]; then
        echo "GPU-Optimized Machine Types:"
        echo "----------------------------------------"

        for zone in "${zones_to_query[@]}"; do
            echo "Zone: $zone"
            gcloud compute machine-types list \
                --zones="$zone" \
                --filter="name:a2- OR name:g2- OR name:a3-" \
                --format="table[box](name,guestCpus,memoryMb.yesno(no='',yes=size()),description)" \
                --project="$PROJECT" 2>/dev/null | head -25
            echo ""
            break  # Only show one zone for GPUs
        done

        echo "Note: For GPUs attached to standard machine types (n1, n2, e2),"
        echo "use --accelerator flag with the base machine type."
        echo "Example: --machine-type=n1-standard-4 --accelerator=nvidia-tesla-t4"
        echo ""
    fi
}

# ============================================================================
# TPU Zone Data (Hardcoded - Fast but may become stale)
# ============================================================================

# TPU v6e supported zones (from https://cloud.google.com/kubernetes-engine/docs/concepts/plan-tpus)
declare -A TPU_V6E_ZONES=(
    ["us-central1-b"]="US Central"
    ["us-east1-d"]="US East"
    ["us-east5-a"]="US East (Columbus)"
    ["us-east5-b"]="US East (Columbus)"
    ["us-south1-a"]="US South (Dallas)"
    ["us-south1-b"]="US South (Dallas)"
    ["europe-west4-a"]="Europe (Netherlands)"
    ["asia-northeast1-b"]="Asia (Tokyo)"
    ["southamerica-west1-a"]="South America (Santiago)"
)

# TPU v5e supported zones
declare -A TPU_V5E_ZONES=(
    ["europe-west4-b"]="Europe (Netherlands)"
    ["us-central1-a"]="US Central"
    ["us-south1-a"]="US South (Dallas)"
    ["us-west1-c"]="US West (Oregon)"
    ["us-west4-a"]="US West (Las Vegas)"
)

# TPU v5p supported zones
declare -A TPU_V5P_ZONES=(
    ["europe-west4-b"]="Europe (Netherlands)"
    ["us-central1-a"]="US Central"
    ["us-east5-a"]="US East (Columbus)"
)

# ============================================================================
# GPU Zone Data
# ============================================================================

# NVIDIA T4 GPU zones (widely available, cost-effective)
declare -A GPU_T4_ZONES=(
    ["us-central1-a"]="US Central ⭐"
    ["us-central1-b"]="US Central"
    ["us-central1-c"]="US Central"
    ["us-central1-f"]="US Central"
    ["us-east1-b"]="US East"
    ["us-east1-c"]="US East"
    ["us-east1-d"]="US East"
    ["us-east4-a"]="US East (Virginia)"
    ["us-east4-b"]="US East (Virginia)"
    ["us-east4-c"]="US East (Virginia)"
    ["us-west1-a"]="US West (Oregon)"
    ["us-west1-b"]="US West (Oregon)"
    ["us-west2-b"]="US West (Los Angeles)"
    ["us-west2-c"]="US West (Los Angeles)"
    ["us-west4-a"]="US West (Las Vegas)"
    ["us-west4-b"]="US West (Las Vegas)"
    ["europe-west1-b"]="Europe (Belgium)"
    ["europe-west1-c"]="Europe (Belgium)"
    ["europe-west4-a"]="Europe (Netherlands)"
    ["europe-west4-b"]="Europe (Netherlands)"
    ["asia-east1-a"]="Asia (Taiwan)"
    ["asia-southeast1-a"]="Asia (Singapore)"
)

# NVIDIA A100 GPU zones (premium, high-performance)
declare -A GPU_A100_ZONES=(
    ["us-central1-a"]="US Central"
    ["us-central1-b"]="US Central"
    ["us-central1-c"]="US Central"
    ["us-east1-c"]="US East"
    ["us-east4-a"]="US East (Virginia)"
    ["us-east4-b"]="US East (Virginia)"
    ["us-west1-a"]="US West (Oregon)"
    ["us-west1-b"]="US West (Oregon)"
    ["europe-west4-a"]="Europe (Netherlands)"
    ["europe-west4-b"]="Europe (Netherlands)"
    ["asia-southeast1-c"]="Asia (Singapore)"
    ["asia-northeast1-a"]="Asia (Tokyo)"
    ["asia-northeast1-c"]="Asia (Tokyo)"
)

# NVIDIA L4 GPU zones (newer, efficient)
declare -A GPU_L4_ZONES=(
    ["us-central1-a"]="US Central"
    ["us-central1-b"]="US Central"
    ["us-central1-c"]="US Central"
    ["us-east1-c"]="US East"
    ["us-east4-a"]="US East (Virginia)"
    ["us-east4-b"]="US East (Virginia)"
    ["us-west1-a"]="US West (Oregon)"
    ["us-west1-b"]="US West (Oregon)"
    ["us-west4-b"]="US West (Las Vegas)"
    ["europe-west1-b"]="Europe (Belgium)"
    ["europe-west4-a"]="Europe (Netherlands)"
    ["asia-southeast1-b"]="Asia (Singapore)"
    ["asia-northeast1-b"]="Asia (Tokyo)"
)

# NVIDIA H100 GPU zones (latest generation)
declare -A GPU_H100_ZONES=(
    ["us-central1-a"]="US Central"
    ["us-central1-b"]="US Central"
    ["us-east4-a"]="US East (Virginia)"
    ["us-east4-c"]="US East (Virginia)"
    ["us-west1-a"]="US West (Oregon)"
    ["us-west4-b"]="US West (Las Vegas)"
    ["europe-west4-a"]="Europe (Netherlands)"
    ["asia-southeast1-c"]="Asia (Singapore)"
)

# ============================================================================
# Helper Functions
# ============================================================================

show_usage() {
    cat <<EOF
========================================
GKE Accelerator Availability Checker
========================================

Usage: $0 [OPTIONS] [ZONE]

Options:
  --type <tpu|gpu|all>    Filter by accelerator type (default: all)
  --region <pattern>      Filter by region pattern (e.g., "us-central1", "us-*")
  --zone <zone>           Validate specific zone
  --api                   Fetch live data from Google Cloud API (slower, always current)
  --show-machine-types    Display available machine types from API (helps find new types)
  --help, -h              Show this help message

Data Sources:
  Default: Hardcoded zone data (fast, updated Feb 2026, may become stale)
  --api:   Live Google Cloud API (10-20s, always current, requires gcloud auth)

Positional Arguments:
  ZONE                    Validate specific zone (same as --zone)

Examples:
  $0                                    # Show all accelerators (hardcoded data)
  $0 --api                              # Show all accelerators (live API data)
  $0 --type tpu                         # Show only TPU zones
  $0 --type gpu                         # Show only GPU zones
  $0 --type gpu --region us-central1    # Show GPU zones in us-central1
  $0 --api --type gpu                   # Show GPU zones from live API
  $0 --region "us-*"                    # Show all US zones
  $0 us-central1-a                      # Validate us-central1-a
  $0 --type gpu --zone us-central1-a    # Validate us-central1-a for GPUs
  $0 --show-machine-types --type tpu    # Show available TPU machine types
  $0 --show-machine-types --type gpu    # Show available GPU machine types

Supported Accelerator Types:
  TPU: v6e (Trillium), v5e, v5p
  GPU: T4, A100, L4, H100

Project: $PROJECT
========================================
EOF
}

filter_by_region() {
    local zone="$1"

    # No filter = include all
    if [[ -z "$REGION_FILTER" ]]; then
        return 0
    fi

    # Support wildcard patterns (us-* matches us-central1-a, us-east1-b, etc.)
    if [[ "$REGION_FILTER" == *"*"* ]]; then
        local pattern="${REGION_FILTER//\*/.*}"
        if [[ "$zone" =~ ^$pattern ]]; then
            return 0
        fi
    else
        # Exact region match (us-central1 matches us-central1-a, us-central1-b, etc.)
        if [[ "$zone" == "$REGION_FILTER"* ]]; then
            return 0
        fi
    fi

    return 1
}

display_zones() {
    local -n zones_array=$1
    local title="$2"
    local marker="$3"

    echo "$title"
    echo "----------------------------------------"

    # Collect matching zones into an array
    local -a zone_lines=()
    for zone in "${!zones_array[@]}"; do
        if filter_by_region "$zone"; then
            local region="${zones_array[$zone]}"
            zone_lines+=("$(printf "  %-20s %s" "$zone" "$region")")
        fi
    done

    # Display sorted output if we found matches
    if [[ ${#zone_lines[@]} -gt 0 ]]; then
        printf '%s\n' "${zone_lines[@]}" | sort
    else
        echo "  (No zones match the filter)"
    fi

    echo ""
}

validate_zone() {
    local zone="$1"

    echo "========================================="
    echo "Validating Zone: $zone"
    echo "========================================="

    local found_any=0

    # Check TPU support (if type=all or type=tpu)
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "tpu" ]]; then
        if [[ -v TPU_V6E_ZONES[$zone] ]]; then
            echo "✅ TPU v6e (Trillium) is SUPPORTED in $zone"
            echo "   Region: ${TPU_V6E_ZONES[$zone]}"
            echo "   Machine types: ct6e-standard-1t, ct6e-standard-4t, ct6e-standard-8t"
            found_any=1
        else
            echo "❌ TPU v6e (Trillium) is NOT SUPPORTED in $zone"
        fi

        if [[ -v TPU_V5E_ZONES[$zone] ]]; then
            echo "✅ TPU v5e is SUPPORTED in $zone"
            echo "   Region: ${TPU_V5E_ZONES[$zone]}"
            found_any=1
        else
            echo "❌ TPU v5e is NOT SUPPORTED in $zone"
        fi

        if [[ -v TPU_V5P_ZONES[$zone] ]]; then
            echo "✅ TPU v5p is SUPPORTED in $zone"
            echo "   Region: ${TPU_V5P_ZONES[$zone]}"
            found_any=1
        else
            echo "❌ TPU v5p is NOT SUPPORTED in $zone"
        fi

        echo ""
    fi

    # Check GPU support (if type=all or type=gpu)
    if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "gpu" ]]; then
        if [[ -v GPU_T4_ZONES[$zone] ]]; then
            echo "✅ NVIDIA T4 GPU is SUPPORTED in $zone"
            echo "   Region: ${GPU_T4_ZONES[$zone]}"
            echo "   Machine types: n1-standard-* with --accelerator type=nvidia-tesla-t4"
            found_any=1
        else
            echo "❌ NVIDIA T4 GPU is NOT SUPPORTED in $zone"
        fi

        if [[ -v GPU_A100_ZONES[$zone] ]]; then
            echo "✅ NVIDIA A100 GPU is SUPPORTED in $zone"
            echo "   Region: ${GPU_A100_ZONES[$zone]}"
            echo "   Machine types: a2-* family"
            found_any=1
        else
            echo "❌ NVIDIA A100 GPU is NOT SUPPORTED in $zone"
        fi

        if [[ -v GPU_L4_ZONES[$zone] ]]; then
            echo "✅ NVIDIA L4 GPU is SUPPORTED in $zone"
            echo "   Region: ${GPU_L4_ZONES[$zone]}"
            echo "   Machine types: g2-standard-* family"
            found_any=1
        else
            echo "❌ NVIDIA L4 GPU is NOT SUPPORTED in $zone"
        fi

        if [[ -v GPU_H100_ZONES[$zone] ]]; then
            echo "✅ NVIDIA H100 GPU is SUPPORTED in $zone"
            echo "   Region: ${GPU_H100_ZONES[$zone]}"
            echo "   Machine types: a3-* family"
            found_any=1
        else
            echo "❌ NVIDIA H100 GPU is NOT SUPPORTED in $zone"
        fi

        echo ""
    fi

    # Verify GKE is available
    echo "Checking GKE availability in $zone..."
    if gcloud container get-server-config --zone=$zone --project=$PROJECT &> /dev/null; then
        echo "✅ GKE is available in $zone"

        # Get latest version
        LATEST_VERSION=$(gcloud container get-server-config --zone=$zone --project=$PROJECT --format="value(channels[0].defaultVersion)" 2>/dev/null || echo "unknown")
        echo "   Latest GKE version: $LATEST_VERSION"
    else
        echo "❌ GKE is NOT available in $zone"
    fi

    echo ""

    if [[ $found_any -eq 0 ]]; then
        echo "⚠️  No accelerators of type '$TYPE_FILTER' found in $zone"
    fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

# Default filters
TYPE_FILTER="all"
REGION_FILTER=""
ZONE_VALIDATE=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            TYPE_FILTER="$2"
            shift 2
            ;;
        --region)
            REGION_FILTER="$2"
            shift 2
            ;;
        --zone)
            ZONE_VALIDATE="$2"
            shift 2
            ;;
        --api)
            USE_API=true
            shift
            ;;
        --show-machine-types)
            SHOW_MACHINE_TYPES=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # Positional argument (zone validation)
            ZONE_VALIDATE="$1"
            shift
            ;;
    esac
done

# Validate TYPE_FILTER
if [[ ! "$TYPE_FILTER" =~ ^(tpu|gpu|all)$ ]]; then
    echo "Error: --type must be 'tpu', 'gpu', or 'all'"
    exit 1
fi

# Load API data if requested
if [[ "$USE_API" == "true" ]]; then
    load_api_data
fi

# ============================================================================
# Main Script
# ============================================================================

# If machine types display requested, show and exit
if [[ "$SHOW_MACHINE_TYPES" == "true" ]]; then
    fetch_and_display_machine_types
    exit 0
fi

# If zone validation requested, run that and exit
if [[ -n "$ZONE_VALIDATE" ]]; then
    validate_zone "$ZONE_VALIDATE"
    exit 0
fi

# Display header
echo "========================================="
echo "GKE Accelerator Availability Checker"
echo "========================================="
echo "Project: $PROJECT"
if [[ "$USE_API" == "true" ]]; then
    echo "Data source: Live Google Cloud API"
else
    echo "Data source: Hardcoded (as of Feb 2026)"
fi
if [[ -n "$REGION_FILTER" ]]; then
    echo "Filter: type=$TYPE_FILTER, region=$REGION_FILTER"
else
    echo "Filter: type=$TYPE_FILTER"
fi
echo ""

# Display TPU zones (if type=all or type=tpu)
if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "tpu" ]]; then
    echo "========================================="
    echo "TPU Accelerators"
    echo "========================================="
    echo ""

    display_zones TPU_V6E_ZONES "TPU v6e (Trillium) Supported Zones in GKE:"
    display_zones TPU_V5E_ZONES "TPU v5e Supported Zones in GKE:"
    display_zones TPU_V5P_ZONES "TPU v5p Supported Zones in GKE:"
fi

# Display GPU zones (if type=all or type=gpu)
if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "gpu" ]]; then
    echo "========================================="
    echo "GPU Accelerators"
    echo "========================================="
    echo ""

    display_zones GPU_T4_ZONES "NVIDIA T4 GPU Supported Zones in GKE:" "⭐"
    display_zones GPU_A100_ZONES "NVIDIA A100 GPU Supported Zones in GKE:"
    display_zones GPU_L4_ZONES "NVIDIA L4 GPU Supported Zones in GKE:"
    display_zones GPU_H100_ZONES "NVIDIA H100 GPU Supported Zones in GKE:"
fi

# Display recommended zones
echo "========================================="
echo "Recommended Zones"
echo "========================================="
echo ""

if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "tpu" ]]; then
    if filter_by_region "us-central1-b" || filter_by_region "us-south1-a" || [[ -z "$REGION_FILTER" ]]; then
        echo "TPU v6e (Trillium) - Best Performance:"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-central1 ]] && echo "  1. us-central1-b    (Central US)"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-south1 ]] && echo "  2. us-south1-a      (Dallas)"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-south1 ]] && echo "  3. us-south1-b      (Dallas)"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-east5 ]] && echo "  4. us-east5-a       (Columbus)"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-east5 ]] && echo "  5. us-east5-b       (Columbus)"
        echo ""
    fi

    if filter_by_region "us-central1-a" || filter_by_region "us-south1-a" || [[ -z "$REGION_FILTER" ]]; then
        echo "TPU v5e - Wider Availability:"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-central1 ]] && echo "  1. us-central1-a    (Central US)"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-south1 ]] && echo "  2. us-south1-a      (Dallas)"
        echo ""
    fi
fi

if [[ "$TYPE_FILTER" == "all" || "$TYPE_FILTER" == "gpu" ]]; then
    if filter_by_region "us-central1-a" || [[ -z "$REGION_FILTER" ]]; then
        echo "GPU - Currently Used in Deployments:"
        [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us-central1 ]] && echo "  ⭐ us-central1-a    (T4 GPU - Pattern 1, 2, 3 deployments)"
        echo ""
    fi

    if [[ -z "$REGION_FILTER" || "$REGION_FILTER" =~ us ]]; then
        echo "GPU - Best US Availability (T4):"
        echo "  1. us-central1-a/b/c/f"
        echo "  2. us-east1-b/c/d"
        echo "  3. us-east4-a/b/c"
        echo "  4. us-west1-a/b"
        echo ""
    fi
fi

echo "========================================="
echo ""
echo "Usage:"
echo "  $0 [OPTIONS] [ZONE]"
echo ""
echo "Examples:"
echo "  $0 --type gpu --region us-central1    # Show GPU zones in us-central1"
echo "  $0 us-central1-a                      # Validate us-central1-a"
echo "  $0 --help                             # Show full help"
echo "========================================="
