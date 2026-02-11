#!/bin/bash
# Comprehensive benchmark for llm-d-infra-xks-gke-tpu Pattern 1
# Tests throughput and latency under various load conditions
#
# Usage: ./benchmark-cluster.sh [protocol] [gateway_ip]
# Examples:
#   ./benchmark-cluster.sh http 34.7.208.8
#   ./benchmark-cluster.sh https 34.7.208.8
#   ./benchmark-cluster.sh  # Auto-detect Gateway IP

set -euo pipefail

# Configuration
PROTOCOL=${1:-"http"}
GATEWAY_IP=${2:-""}
BASE_URL_PREFIX="/llm-d-inference-scheduling/qwen2-3b-pattern1"
MODEL="Qwen/Qwen2.5-3B-Instruct"
NAMESPACE="llm-d-inference-scheduling"

# Auto-detect Gateway IP if not provided
if [ -z "$GATEWAY_IP" ]; then
    echo "Auto-detecting Gateway IP..."
    GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -z "$GATEWAY_IP" ]; then
        echo "ERROR: Could not auto-detect Gateway IP"
        echo "Usage: $0 [protocol] [gateway_ip]"
        echo "Example: $0 http 34.7.208.8"
        exit 1
    fi
    echo "Detected Gateway IP: $GATEWAY_IP"
fi

BASE_URL="${PROTOCOL}://${GATEWAY_IP}"
ENDPOINT="$BASE_URL${BASE_URL_PREFIX}/v1/completions"

# Benchmark scenarios
SCENARIOS=(
  "1,1,Baseline (1 req, concurrency 1)"
  "10,1,Serial (10 req, concurrency 1)"
  "20,5,Light load (20 req, concurrency 5)"
  "50,10,Medium load (50 req, concurrency 10)"
  "100,20,Heavy load (100 req, concurrency 20)"
)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Add curl opts for HTTPS
CURL_OPTS=""
AB_OPTS=""
if [ "$PROTOCOL" = "https" ]; then
    CURL_OPTS="-k"
    echo -e "${YELLOW}Warning: Apache Bench may not work with self-signed HTTPS certs${NC}"
    echo "Consider using HTTP for benchmarking: ./benchmark-cluster.sh http $GATEWAY_IP"
    echo ""
fi

echo -e "${BLUE}========================================"
echo "  llm-d Pattern 1 Benchmark"
echo "  (GKE Gateway + KServe on TPU v6e)"
echo "========================================${NC}"
echo "Endpoint: $ENDPOINT"
echo "Model: $MODEL"
echo "Protocol: $PROTOCOL"
echo "Namespace: $NAMESPACE"
echo ""

# Check prerequisites
if ! command -v ab &> /dev/null; then
    echo -e "${RED}Error: Apache Bench (ab) not found${NC}"
    echo "Install with:"
    echo "  Fedora/RHEL: sudo dnf install httpd-tools"
    echo "  Ubuntu/Debian: sudo apt-get install apache2-utils"
    echo ""
    echo "Or use curl-based testing instead"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found (optional, for pretty output)${NC}"
    echo "Install with: sudo dnf install jq"
    echo ""
fi

# Pre-flight check
echo -n "Pre-flight: Checking endpoint... "
PREFLIGHT=$(curl -s $CURL_OPTS -X GET "$BASE_URL${BASE_URL_PREFIX}/v1/models" \
  --connect-timeout 10 --max-time 10 -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")

if [ "$PREFLIGHT" = "200" ]; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED (HTTP $PREFLIGHT)${NC}"
    echo ""
    echo "Cluster appears to be scaled down or unavailable."
    echo "Check cluster status:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl get inferencepool -n $NAMESPACE"
    echo "  kubectl get gateway -n opendatahub"
    echo ""
    echo "To start the cluster (if scaled down):"
    echo "  1. Scale up node pool (if at 0):"
    echo "     gcloud container clusters resize llmd-istio-tpu-pattern1 \\"
    echo "       --node-pool=tpu-v6e-pool --num-nodes=1 \\"
    echo "       --zone=europe-west4-a --project=ecoeng-llmd"
    echo ""
    echo "  2. Redeploy Helm release (if uninstalled):"
    echo "     helm install qwen2-3b-pattern1 llm-d/modelservice \\"
    echo "       -n $NAMESPACE -f helm-values/pattern1-tpu-values.yaml \\"
    echo "       --wait --timeout 20m"
    echo ""
    echo "  3. Wait ~10-15 minutes for pod to be ready (model download + TPU init)"
    exit 1
fi

# Create results directory
RESULTS_DIR="../benchmarks/results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_FILE="$RESULTS_DIR/benchmark_summary_${TIMESTAMP}.txt"

# Start summary file
{
    echo "================================================"
    echo "  llm-d-infra-xks-gke-tpu Pattern 1 Benchmark"
    echo "================================================"
    echo "Date: $(date)"
    echo "Endpoint: $ENDPOINT"
    echo "Model: $MODEL"
    echo "Protocol: $PROTOCOL"
    echo "Deployment: GKE Gateway + KServe on TPU v6e-4"
    echo ""
} > "$SUMMARY_FILE"

echo ""
echo "Running benchmark scenarios..."
echo ""

# Run each scenario
for scenario in "${SCENARIOS[@]}"; do
    IFS=',' read -r num_requests concurrency description <<< "$scenario"

    echo -e "${BLUE}Scenario: $description${NC}"
    echo "  Requests: $num_requests, Concurrency: $concurrency"

    # Create POST data file
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" << EOF
{
  "model": "$MODEL",
  "prompt": "Explain quantum computing in one sentence:",
  "max_tokens": 50,
  "temperature": 0.7
}
EOF

    # Output files
    TSV_FILE="$RESULTS_DIR/ab_${num_requests}req_${concurrency}c_${TIMESTAMP}.tsv"
    AB_OUTPUT="$RESULTS_DIR/ab_${num_requests}req_${concurrency}c_${TIMESTAMP}.txt"

    # Run Apache Bench
    if ab -n "$num_requests" \
        -c "$concurrency" \
        -p "$TMP_FILE" \
        -T "application/json" \
        -g "$TSV_FILE" \
        "$ENDPOINT" > "$AB_OUTPUT" 2>&1; then

        # Extract key metrics
        REQUESTS_PER_SEC=$(grep "Requests per second:" "$AB_OUTPUT" | awk '{print $4}')
        TIME_PER_REQUEST=$(grep "Time per request:" "$AB_OUTPUT" | grep "mean" | head -1 | awk '{print $4}')
        TIME_PER_REQUEST_CONCURRENT=$(grep "Time per request:" "$AB_OUTPUT" | grep "mean, across all concurrent requests" | awk '{print $4}')
        FAILED_REQUESTS=$(grep "Failed requests:" "$AB_OUTPUT" | awk '{print $3}')

        # Extract percentiles
        P50=$(grep "50%" "$AB_OUTPUT" | awk '{print $2}')
        P95=$(grep "95%" "$AB_OUTPUT" | awk '{print $2}')
        P99=$(grep "99%" "$AB_OUTPUT" | awk '{print $2}')

        echo -e "  ${GREEN}✓ Complete${NC}"
        echo "  Throughput: $REQUESTS_PER_SEC req/sec"
        echo "  Latency (mean): ${TIME_PER_REQUEST}ms"
        echo "  Latency (P50): ${P50}ms"
        echo "  Latency (P95): ${P95}ms"
        echo "  Latency (P99): ${P99}ms"
        echo "  Failed: $FAILED_REQUESTS"

        # Add to summary
        {
            echo "----------------------------------------"
            echo "Scenario: $description"
            echo "  Requests: $num_requests"
            echo "  Concurrency: $concurrency"
            echo "  Throughput: $REQUESTS_PER_SEC req/sec"
            echo "  Latency (mean): ${TIME_PER_REQUEST}ms"
            echo "  Latency (P50): ${P50}ms"
            echo "  Latency (P95): ${P95}ms"
            echo "  Latency (P99): ${P99}ms"
            echo "  Failed requests: $FAILED_REQUESTS"
            echo ""
        } >> "$SUMMARY_FILE"

    else
        echo -e "  ${RED}✗ Failed${NC}"
        echo "  Check $AB_OUTPUT for details"

        {
            echo "----------------------------------------"
            echo "Scenario: $description - FAILED"
            echo "  See $AB_OUTPUT for details"
            echo ""
        } >> "$SUMMARY_FILE"
    fi

    rm "$TMP_FILE"
    echo ""
done

# EPP routing test (prefix cache)
echo -e "${BLUE}EPP Routing Test (Prefix Cache)${NC}"
echo "Sending 5 similar requests to test prefix caching..."

PROMPT="Explain Kubernetes in one sentence:"
CACHE_TEST_FILE="$RESULTS_DIR/cache_test_${TIMESTAMP}.txt"

{
    echo "================================================"
    echo "  EPP Prefix Cache Test"
    echo "================================================"
    echo "Prompt: $PROMPT"
    echo ""
} > "$CACHE_TEST_FILE"

for i in {1..5}; do
    echo -n "  Request $i: "
    START=$(date +%s%N)
    RESPONSE=$(curl -s $CURL_OPTS -X POST "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"$PROMPT\",
        \"max_tokens\": 30
      }")
    END=$(date +%s%N)
    LATENCY=$(( (END - START) / 1000000 ))

    if echo "$RESPONSE" | grep -q "choices"; then
        echo -e "${GREEN}✓ ${LATENCY}ms${NC}"
        echo "Request $i: ${LATENCY}ms - Success" >> "$CACHE_TEST_FILE"
    else
        echo -e "${RED}✗ Failed${NC}"
        echo "Request $i: Failed" >> "$CACHE_TEST_FILE"
    fi
done

echo -e "${YELLOW}Note: Requests 2-5 should be faster if EPP prefix caching is working${NC}"
echo ""

{
    echo ""
    echo "Expected behavior:"
    echo "  - Request 1: Full inference (slower)"
    echo "  - Requests 2-5: Prefix cache hit (faster)"
    echo "  - Latency reduction: ~20-30% expected"
} >> "$CACHE_TEST_FILE"

# Final summary
{
    echo "================================================"
    echo "Results saved to: $RESULTS_DIR"
    echo "================================================"
} >> "$SUMMARY_FILE"

echo -e "${GREEN}========================================"
echo "  Benchmark Complete"
echo "========================================${NC}"
echo ""
echo "Summary:"
cat "$SUMMARY_FILE"
echo ""
echo "Detailed results:"
echo "  Summary: $SUMMARY_FILE"
echo "  Cache test: $CACHE_TEST_FILE"
echo "  TSV files: $RESULTS_DIR/ab_*_${TIMESTAMP}.tsv"
echo "  Raw output: $RESULTS_DIR/ab_*_${TIMESTAMP}.txt"
echo ""
echo "To visualize results:"
echo "  # Import TSV files into Excel/Google Sheets"
echo "  # Or use gnuplot:"
echo "  gnuplot -e 'set datafile separator \"\t\"; plot \"$RESULTS_DIR/ab_100req_20c_${TIMESTAMP}.tsv\" using 2:5 with linespoints title \"Response Time\"'"
echo ""
echo "To check EPP scheduler logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=scheduler --tail=100"
echo ""
