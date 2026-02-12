#!/bin/bash
# Comprehensive pre-flight check for GKE LLM deployments
# Validates all requirements before deployment

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall status
ALL_CHECKS_PASSED=true
WARNINGS_COUNT=0

show_usage() {
    cat <<EOF
=========================================
GKE LLM Deployment Pre-Flight Check
=========================================

Usage: $0 --deployment <path> [OPTIONS]

Required:
  --deployment <path>     Path to deployment directory (e.g., gateway-api/pattern1-baseline)

Optional:
  --cluster <name>        Cluster name to validate (creates if not specified)
  --zone <zone>           Zone for deployment (default: us-central1-a)
  --accelerator <type>    Accelerator type: gpu or tpu (default: gpu)
  --project <project>     GCP project ID (default: from gcloud config)
  --skip-tools            Skip tool installation checks
  --skip-cluster          Skip cluster validation checks
  --detailed              Show detailed output for all checks

Examples:
  # Check Pattern 1 GPU deployment
  $0 --deployment gateway-api/pattern1-baseline

  # Check Pattern 2 with existing cluster
  $0 --deployment gateway-api/pattern2-multimodel \\
    --cluster llm-d-cluster \\
    --zone us-central1-a

  # Check Istio/KServe Pattern 1 TPU deployment
  $0 --deployment istio-kserve/pattern1-baseline \\
    --accelerator tpu \\
    --zone us-central1-b

  # Check with detailed output
  $0 --deployment gateway-api/pattern3-caching --detailed

=========================================
EOF
}

# Parse arguments
DEPLOYMENT_PATH=""
CLUSTER_NAME=""
ZONE="us-central1-a"
ACCELERATOR_TYPE="gpu"
PROJECT_ID=""
SKIP_TOOLS=false
SKIP_CLUSTER=false
DETAILED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment)
            DEPLOYMENT_PATH="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --accelerator)
            ACCELERATOR_TYPE="$2"
            shift 2
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --skip-tools)
            SKIP_TOOLS=true
            shift
            ;;
        --skip-cluster)
            SKIP_CLUSTER=true
            shift
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$DEPLOYMENT_PATH" ]]; then
    echo -e "${RED}Error: --deployment is required${NC}"
    show_usage
    exit 1
fi

# Determine script directory (deployments/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="${SCRIPT_DIR}/${DEPLOYMENT_PATH}"

# Validate deployment directory exists
if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
    echo -e "${RED}Error: Deployment directory not found: $DEPLOYMENT_DIR${NC}"
    exit 1
fi

# Detect deployment pattern and technology stack
PATTERN_NAME=$(basename "$DEPLOYMENT_PATH")
TECH_STACK=$(dirname "$DEPLOYMENT_PATH")

# Set project ID if not specified
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

echo "========================================="
echo "GKE LLM Deployment Pre-Flight Check"
echo "========================================="
echo "Deployment: $DEPLOYMENT_PATH"
echo "Technology Stack: $TECH_STACK"
echo "Pattern: $PATTERN_NAME"
echo "Zone: $ZONE"
echo "Accelerator: $ACCELERATOR_TYPE"
echo "Project: ${PROJECT_ID:-'not set'}"
[[ -n "$CLUSTER_NAME" ]] && echo "Cluster: $CLUSTER_NAME"
echo ""

# ============================================================================
# Check 1: Required Tools
# ============================================================================
if [ "$SKIP_TOOLS" = false ]; then
    echo "========================================="
    echo "Check 1: Required Tools"
    echo "========================================="

    REQUIRED_TOOLS=("gcloud" "kubectl" "git")

    # Add stack-specific tools
    if [[ "$TECH_STACK" == "gateway-api" ]]; then
        REQUIRED_TOOLS+=("helm" "helmfile")
    elif [[ "$TECH_STACK" == "istio-kserve" ]]; then
        REQUIRED_TOOLS+=("kubectl")
    fi

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &> /dev/null; then
            VERSION=$($tool version --short 2>/dev/null || $tool --version 2>/dev/null | head -1 || echo "installed")
            echo -e "${GREEN}✅ $tool${NC} - $VERSION"
        else
            echo -e "${RED}❌ $tool - NOT FOUND${NC}"
            echo "   Install: https://cloud.google.com/sdk/docs/install (for gcloud)"
            ALL_CHECKS_PASSED=false
        fi
    done

    echo ""
fi

# ============================================================================
# Check 2: GCP Authentication and Project
# ============================================================================
echo "========================================="
echo "Check 2: GCP Authentication"
echo "========================================="

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
if [[ -n "$ACTIVE_ACCOUNT" ]]; then
    echo -e "${GREEN}✅ Authenticated as: $ACTIVE_ACCOUNT${NC}"
else
    echo -e "${RED}❌ Not authenticated to gcloud${NC}"
    echo "   Run: gcloud auth login"
    ALL_CHECKS_PASSED=false
fi

if [[ -n "$PROJECT_ID" ]]; then
    # Verify project access
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}✅ Project accessible: $PROJECT_ID${NC}"
    else
        echo -e "${RED}❌ Cannot access project: $PROJECT_ID${NC}"
        ALL_CHECKS_PASSED=false
    fi
else
    echo -e "${RED}❌ No project ID set${NC}"
    echo "   Run: gcloud config set project YOUR_PROJECT_ID"
    ALL_CHECKS_PASSED=false
fi

echo ""

# ============================================================================
# Check 3: IAM Permissions
# ============================================================================
echo "========================================="
echo "Check 3: IAM Permissions"
echo "========================================="

if [[ -n "$PROJECT_ID" && -n "$ACTIVE_ACCOUNT" ]]; then
    REQUIRED_ROLES=("roles/container.admin")

    USER_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --filter="bindings.members:user:$ACTIVE_ACCOUNT" \
        --format="value(bindings.role)" 2>/dev/null || echo "")

    for role in "${REQUIRED_ROLES[@]}"; do
        if echo "$USER_ROLES" | grep -q "$role\|roles/owner\|roles/editor"; then
            echo -e "${GREEN}✅ $role (or equivalent)${NC}"
        else
            echo -e "${YELLOW}⚠️  $role - NOT FOUND${NC}"
            echo "   You may need elevated permissions for cluster creation"
            ((WARNINGS_COUNT++))
        fi
    done
else
    echo -e "${YELLOW}⚠️  Skipping IAM check (authentication required)${NC}"
fi

echo ""

# ============================================================================
# Check 4: Accelerator and Zone Availability
# ============================================================================
echo "========================================="
echo "Check 4: Accelerator Availability"
echo "========================================="

# Determine machine type based on accelerator
MACHINE_TYPE=""
if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
    MACHINE_TYPE="ct6e-standard-4t"
elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
    MACHINE_TYPE="n1-standard-4"
fi

# Use our existing accelerator checker
if [[ -f "$SCRIPT_DIR/check-gke-accelerator-availability.sh" ]]; then
    echo "Running accelerator availability check for $ACCELERATOR_TYPE in $ZONE..."

    # Call checker with specific accelerator type
    CHECKER_OUTPUT=$("$SCRIPT_DIR/check-gke-accelerator-availability.sh" --zone "$ZONE" --type "$ACCELERATOR_TYPE" 2>&1)

    # Check for GKE availability
    if echo "$CHECKER_OUTPUT" | grep -q "✅ GKE is available"; then
        echo -e "${GREEN}✅ GKE is available in $ZONE${NC}"
    else
        echo -e "${RED}❌ GKE is not available in $ZONE${NC}"
        ALL_CHECKS_PASSED=false
    fi

    # Check for specific accelerator availability
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        if echo "$CHECKER_OUTPUT" | grep -q "✅ TPU .* is SUPPORTED"; then
            echo -e "${GREEN}✅ TPU accelerators available in $ZONE${NC}"
            # Show which TPU types are supported
            echo "$CHECKER_OUTPUT" | grep "✅ TPU" | sed 's/^/   /'
        else
            echo -e "${RED}❌ No TPU accelerators available in $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi
    elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        if echo "$CHECKER_OUTPUT" | grep -q "GPU is SUPPORTED"; then
            echo -e "${GREEN}✅ GPU accelerators available in $ZONE${NC}"
            # Show which GPU types are supported
            echo "$CHECKER_OUTPUT" | grep "✅ NVIDIA" | sed 's/^/   /'
        else
            echo -e "${RED}❌ No GPU accelerators available in $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Accelerator checker script not found${NC}"
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 5: Node Pool Prerequisites
# ============================================================================
echo "========================================="
echo "Check 5: Node Pool Prerequisites"
echo "========================================="

if [[ -n "$MACHINE_TYPE" && -f "$SCRIPT_DIR/check-nodepool-prerequisites.sh" ]]; then
    echo "Running comprehensive node pool validation..."

    # Build prerequisites check command
    PREREQ_CMD="$SCRIPT_DIR/check-nodepool-prerequisites.sh --zone $ZONE --machine-type $MACHINE_TYPE"

    if [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        PREREQ_CMD="$PREREQ_CMD --accelerator nvidia-tesla-t4"
    elif [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        PREREQ_CMD="$PREREQ_CMD --tpu-topology 2x2x1"
    fi

    [[ -n "$CLUSTER_NAME" ]] && PREREQ_CMD="$PREREQ_CMD --cluster $CLUSTER_NAME"
    [[ -n "$PROJECT_ID" ]] && PREREQ_CMD="$PREREQ_CMD --project $PROJECT_ID"

    if $PREREQ_CMD 2>&1 | grep -q "All checks PASSED"; then
        echo -e "${GREEN}✅ Node pool prerequisites validated${NC}"
    else
        echo -e "${RED}❌ Node pool prerequisites check failed${NC}"
        echo "   Run manually for details: $PREREQ_CMD"
        ALL_CHECKS_PASSED=false
    fi
else
    echo -e "${YELLOW}⚠️  Node pool prerequisites checker not found${NC}"
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 6: Deployment Configuration Files
# ============================================================================
echo "========================================="
echo "Check 6: Deployment Files"
echo "========================================="

CONFIG_FILES_FOUND=true

# Check for stack-specific files
if [[ "$TECH_STACK" == "gateway-api" ]]; then
    # Check for Helm values file (try both pattern naming conventions)
    VALUES_FILE=$(find "$DEPLOYMENT_DIR" -maxdepth 1 -name "llm-d-pattern*.yaml" -o -name "*values.yaml" 2>/dev/null | head -1)
    if [[ -n "$VALUES_FILE" ]]; then
        echo -e "${GREEN}✅ Helm values file found: $(basename $VALUES_FILE)${NC}"
    else
        echo -e "${YELLOW}⚠️  Helm values file not found (expected llm-d-pattern*-values.yaml)${NC}"
        CONFIG_FILES_FOUND=false
    fi

    # Check for HTTPRoute manifest
    if [[ -f "$DEPLOYMENT_DIR/manifests/httproute.yaml" ]]; then
        echo -e "${GREEN}✅ HTTPRoute manifest found${NC}"
    else
        echo -e "${YELLOW}⚠️  HTTPRoute manifest not found${NC}"
        CONFIG_FILES_FOUND=false
    fi

elif [[ "$TECH_STACK" == "istio-kserve" ]]; then
    # Check for LLMInferenceService manifest
    if find "$DEPLOYMENT_DIR/manifests" -name "*llmisvc*.yaml" 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✅ LLMInferenceService manifest found${NC}"
    else
        echo -e "${YELLOW}⚠️  LLMInferenceService manifest not found${NC}"
        CONFIG_FILES_FOUND=false
    fi
fi

# Check README
if [[ -f "$DEPLOYMENT_DIR/README.md" ]]; then
    echo -e "${GREEN}✅ README.md found${NC}"
else
    echo -e "${YELLOW}⚠️  README.md not found${NC}"
fi

if [ "$CONFIG_FILES_FOUND" = false ]; then
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 7: Secrets and Credentials
# ============================================================================
echo "========================================="
echo "Check 7: Required Secrets"
echo "========================================="

# Check for pull secret (in repo root)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PULL_SECRET_PATH="$REPO_ROOT/11009103-jhull-svc-pull-secret.yaml"
if [[ -f "$PULL_SECRET_PATH" ]]; then
    echo -e "${GREEN}✅ Red Hat pull secret found${NC}"
else
    echo -e "${YELLOW}⚠️  Red Hat pull secret not found: $PULL_SECRET_PATH${NC}"
    echo "   Required for RHAIIS container images"
    ((WARNINGS_COUNT++))
fi

# Check HuggingFace token
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
    echo -e "${GREEN}✅ HuggingFace token set in environment${NC}"
elif [[ -f "$REPO_ROOT/huggingface-token-secret.yaml" ]]; then
    echo -e "${GREEN}✅ HuggingFace token secret file found${NC}"
else
    echo -e "${YELLOW}⚠️  HuggingFace token not found${NC}"
    echo "   Set HUGGINGFACE_TOKEN environment variable or create huggingface-token-secret.yaml"
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 8: Cluster Validation (if cluster specified)
# ============================================================================
if [[ -n "$CLUSTER_NAME" && "$SKIP_CLUSTER" = false ]]; then
    echo "========================================="
    echo "Check 8: Cluster Validation"
    echo "========================================="

    # Check if cluster exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}✅ Cluster $CLUSTER_NAME exists in $ZONE${NC}"

        # Get cluster credentials
        if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
            echo -e "${GREEN}✅ Cluster credentials configured${NC}"

            # Check cluster status
            CLUSTER_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null)
            if [[ "$CLUSTER_STATUS" == "RUNNING" ]]; then
                echo -e "${GREEN}✅ Cluster status: RUNNING${NC}"
            else
                echo -e "${YELLOW}⚠️  Cluster status: $CLUSTER_STATUS${NC}"
                ((WARNINGS_COUNT++))
            fi

            # Check Gateway API CRDs
            if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
                echo -e "${GREEN}✅ Gateway API CRDs installed${NC}"
            else
                echo -e "${YELLOW}⚠️  Gateway API CRDs not found${NC}"
                echo "   May need to enable GKE Gateway controller"
                ((WARNINGS_COUNT++))
            fi

            # Stack-specific checks
            if [[ "$TECH_STACK" == "istio-kserve" ]]; then
                # Check for Istio
                if kubectl get namespace istio-system &>/dev/null; then
                    echo -e "${GREEN}✅ Istio namespace found${NC}"
                else
                    echo -e "${YELLOW}⚠️  Istio not installed${NC}"
                    ((WARNINGS_COUNT++))
                fi

                # Check for KServe CRDs
                if kubectl get crd llminferenceservices.llm.kserve.io &>/dev/null; then
                    echo -e "${GREEN}✅ KServe LLMInferenceService CRD found${NC}"
                else
                    echo -e "${YELLOW}⚠️  KServe CRDs not found${NC}"
                    ((WARNINGS_COUNT++))
                fi
            fi

        else
            echo -e "${RED}❌ Failed to get cluster credentials${NC}"
            ALL_CHECKS_PASSED=false
        fi
    else
        echo -e "${YELLOW}⚠️  Cluster $CLUSTER_NAME not found in $ZONE${NC}"
        echo "   Will be created during deployment"
    fi

    echo ""
fi

# ============================================================================
# Check 9: External Dependencies
# ============================================================================
echo "========================================="
echo "Check 9: External Dependencies"
echo "========================================="

# Check for llm-d repository (for gateway-api deployments)
if [[ "$TECH_STACK" == "gateway-api" ]]; then
    LLM_D_PATH="/home/jhull/devel/llm-d"
    if [[ -d "$LLM_D_PATH" ]]; then
        echo -e "${GREEN}✅ llm-d repository found: $LLM_D_PATH${NC}"

        # Check for helmfile
        if [[ -f "$LLM_D_PATH/helmfile.yaml.gotmpl" ]]; then
            echo -e "${GREEN}✅ llm-d helmfile found${NC}"
        else
            echo -e "${YELLOW}⚠️  llm-d helmfile not found${NC}"
            ((WARNINGS_COUNT++))
        fi
    else
        echo -e "${YELLOW}⚠️  llm-d repository not found: $LLM_D_PATH${NC}"
        echo "   Clone from: https://github.com/llm-d/llm-d.git"
        ((WARNINGS_COUNT++))
    fi
fi

echo ""

# ============================================================================
# Final Summary
# ============================================================================
echo "========================================="
echo "Pre-Flight Check Summary"
echo "========================================="
echo ""

if [ "$ALL_CHECKS_PASSED" = true ]; then
    if [ "$WARNINGS_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✅ ALL CHECKS PASSED!${NC}"
        echo ""
        echo "You are ready to proceed with deployment."
    else
        echo -e "${YELLOW}✅ CRITICAL CHECKS PASSED with $WARNINGS_COUNT warning(s)${NC}"
        echo ""
        echo "You can proceed with deployment, but review warnings above."
    fi

    # Show next steps
    echo ""
    echo "========================================="
    echo "Next Steps"
    echo "========================================="
    echo ""

    if [[ "$TECH_STACK" == "gateway-api" ]]; then
        echo "1. Review deployment guide:"
        echo "   cat $DEPLOYMENT_DIR/README.md"
        echo ""
        echo "2. Deploy via helmfile:"
        echo "   cd /home/jhull/devel/llm-d"
        echo "   helmfile -f helmfile.yaml.gotmpl apply"
        echo ""
        echo "3. Apply HTTPRoute:"
        echo "   kubectl apply -f $DEPLOYMENT_DIR/manifests/httproute.yaml"
    elif [[ "$TECH_STACK" == "istio-kserve" ]]; then
        echo "1. Review deployment guide:"
        echo "   cat $DEPLOYMENT_DIR/docs/cluster-deployment-guide.md"
        echo ""
        echo "2. Deploy LLMInferenceService:"
        echo "   kubectl apply -f $DEPLOYMENT_DIR/manifests/llmisvc-*.yaml"
    fi

    echo ""
    echo "For detailed setup instructions, see:"
    echo "  $DEPLOYMENT_DIR/docs/"

else
    echo -e "${RED}❌ SOME CHECKS FAILED!${NC}"
    echo ""
    echo "Please resolve the issues above before proceeding with deployment."
    echo ""
    echo "Common fixes:"
    echo "  • Install missing tools"
    echo "  • Run: gcloud auth login"
    echo "  • Run: gcloud config set project YOUR_PROJECT_ID"
    echo "  • Request IAM permissions from project admin"
    echo "  • Create required secret files"
    exit 1
fi

echo ""
echo "========================================="
