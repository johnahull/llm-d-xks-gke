#!/bin/bash
# Check GKE TPU availability in zones
# This script validates that TPUs are actually supported in GKE (not just as VMs)

set -e

PROJECT=${PROJECT:-ecoeng-llmd}

echo "========================================="
echo "GKE TPU Availability Checker"
echo "========================================="
echo "Project: $PROJECT"
echo ""

# Official GKE TPU v6e supported zones (from https://cloud.google.com/kubernetes-engine/docs/concepts/plan-tpus)
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

echo "TPU v6e (Trillium) Supported Zones in GKE:"
echo "----------------------------------------"
for zone in "${!TPU_V6E_ZONES[@]}"; do
    region="${TPU_V6E_ZONES[$zone]}"
    printf "  %-20s %s\n" "$zone" "$region"
done | sort

echo ""
echo "TPU v5e Supported Zones in GKE:"
echo "----------------------------------------"
for zone in "${!TPU_V5E_ZONES[@]}"; do
    region="${TPU_V5E_ZONES[$zone]}"
    printf "  %-20s %s\n" "$zone" "$region"
done | sort

echo ""
echo "TPU v5p Supported Zones in GKE:"
echo "----------------------------------------"
for zone in "${!TPU_V5P_ZONES[@]}"; do
    region="${TPU_V5P_ZONES[$zone]}"
    printf "  %-20s %s\n" "$zone" "$region"
done | sort

echo ""
echo "========================================="
echo "Recommended Zones for South/Central US:"
echo "========================================="
echo ""
echo "TPU v6e (Trillium) - Best Performance:"
echo "  1. us-central1-b    (Central US)"
echo "  2. us-south1-a      (Dallas)"
echo "  3. us-south1-b      (Dallas)"
echo "  4. us-east5-a       (Columbus)"
echo "  5. us-east5-b       (Columbus)"
echo ""
echo "TPU v5e - Wider Availability:"
echo "  1. us-central1-a    (Central US)"
echo "  2. us-south1-a      (Dallas)"
echo ""

# Check if a specific zone was requested
if [ -n "$1" ]; then
    ZONE=$1
    echo "========================================="
    echo "Validating Zone: $ZONE"
    echo "========================================="

    # Check v6e support
    if [[ -v TPU_V6E_ZONES[$ZONE] ]]; then
        echo "✅ TPU v6e (Trillium) is SUPPORTED in $ZONE"
        echo "   Region: ${TPU_V6E_ZONES[$ZONE]}"
        echo "   Machine types: ct6e-standard-1t, ct6e-standard-4t, ct6e-standard-8t"
    else
        echo "❌ TPU v6e (Trillium) is NOT SUPPORTED in $ZONE"
    fi

    # Check v5e support
    if [[ -v TPU_V5E_ZONES[$ZONE] ]]; then
        echo "✅ TPU v5e is SUPPORTED in $ZONE"
        echo "   Region: ${TPU_V5E_ZONES[$ZONE]}"
    else
        echo "❌ TPU v5e is NOT SUPPORTED in $ZONE"
    fi

    # Check v5p support
    if [[ -v TPU_V5P_ZONES[$ZONE] ]]; then
        echo "✅ TPU v5p is SUPPORTED in $ZONE"
        echo "   Region: ${TPU_V5P_ZONES[$ZONE]}"
    else
        echo "❌ TPU v5p is NOT SUPPORTED in $ZONE"
    fi

    echo ""

    # Verify GKE is available
    echo "Checking GKE availability in $ZONE..."
    if gcloud container get-server-config --zone=$ZONE --project=$PROJECT &> /dev/null; then
        echo "✅ GKE is available in $ZONE"

        # Get latest version
        LATEST_VERSION=$(gcloud container get-server-config --zone=$ZONE --project=$PROJECT --format="value(channels[0].defaultVersion)" 2>/dev/null || echo "unknown")
        echo "   Latest GKE version: $LATEST_VERSION"
    else
        echo "❌ GKE is NOT available in $ZONE"
    fi
fi

echo ""
echo "Usage:"
echo "  $0 [zone]    - Validate specific zone"
echo ""
echo "Examples:"
echo "  $0 us-central1-b      # Validate us-central1-b for TPU support"
echo "  $0 us-south1-a        # Validate us-south1-a for TPU support"
echo "========================================="
