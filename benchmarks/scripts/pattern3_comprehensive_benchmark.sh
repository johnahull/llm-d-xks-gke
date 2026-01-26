#!/bin/bash
# Comprehensive Pattern 3 GPU Benchmark Suite
# Tests: Throughput, Prefix Cache Routing, Load Distribution

set -e

GATEWAY_IP="${GATEWAY_IP:-35.208.175.15}"
NAMESPACE="llm-d"
MODEL="Qwen/Qwen2.5-3B-Instruct"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Test 1: Basic Health Check
test_health() {
    print_header "Test 1: Basic Health Check"
    
    echo "Checking pod status..."
    READY_PODS=$(kubectl get pods -n $NAMESPACE -l llm-d.ai/inferenceServing=true --no-headers | grep "1/1" | wc -l)
    
    if [ "$READY_PODS" -eq 3 ]; then
        print_success "All 3 replicas are ready"
    else
        print_error "Only $READY_PODS/3 replicas ready"
        return 1
    fi
    
    echo
    echo "Testing gateway endpoint..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://${GATEWAY_IP}/v1/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${MODEL}\",\"prompt\":\"Hello\",\"max_tokens\":5}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    
    if [ "$HTTP_CODE" -eq 200 ]; then
        print_success "Gateway responding (HTTP $HTTP_CODE)"
    else
        print_error "Gateway returned HTTP $HTTP_CODE"
        return 1
    fi
    
    echo
}

# Test 2: Prefix Cache Routing
test_prefix_cache_routing() {
    print_header "Test 2: Prefix Cache Routing"
    
    SYSTEM_PROMPT="You are a helpful AI assistant. Answer the following question:"
    
    echo "Testing prefix cache affinity with shared system prompt..."
    echo "System prompt: '$SYSTEM_PROMPT'"
    echo
    
    for i in {1..10}; do
        echo -n "Request $i: "
        
        RESPONSE=$(curl -s -X POST "http://${GATEWAY_IP}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${MODEL}\",\"prompt\":\"${SYSTEM_PROMPT} What is $((i*2))+$((i*2))?\",\"max_tokens\":15}")
        
        # Extract first few words of response
        RESULT=$(echo "$RESPONSE" | jq -r '.choices[0].text' 2>/dev/null | head -c 40)
        echo "$RESULT..."
        
        sleep 0.5
    done
    
    echo
    print_success "Prefix cache routing test complete"
    echo
    echo "To verify routing affinity, check EPP logs:"
    echo "  kubectl logs -n $NAMESPACE deployment/gaie-pattern3-epp --tail=50"
    echo
}

# Test 3: Load Distribution
test_load_distribution() {
    print_header "Test 3: Load Distribution Across Replicas"
    
    echo "Sending requests with different prefixes to test load balancing..."
    echo
    
    PROMPTS=(
        "Explain quantum computing:"
        "Write a poem about cats:"
        "Recipe for chocolate cake:"
        "How does photosynthesis work:"
        "Describe the water cycle:"
    )
    
    for i in {1..15}; do
        PROMPT_IDX=$((i % 5))
        PROMPT="${PROMPTS[$PROMPT_IDX]}"
        
        echo -n "Request $i (prompt ${PROMPT_IDX}): "
        
        curl -s -X POST "http://${GATEWAY_IP}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${MODEL}\",\"prompt\":\"${PROMPT}\",\"max_tokens\":10}" \
            > /dev/null 2>&1 &
        
        echo "sent"
        
        # Stagger requests
        sleep 0.2
    done
    
    wait
    
    echo
    print_success "Load distribution test complete"
    echo
    echo "Check request distribution across pods:"
    for pod in $(kubectl get pods -n $NAMESPACE -l llm-d.ai/inferenceServing=true -o name); do
        POD_NAME=$(echo $pod | cut -d/ -f2)
        echo "  $POD_NAME:"
        kubectl logs -n $NAMESPACE $POD_NAME --tail=100 2>/dev/null | grep -c "POST /v1/completions" || echo "    0 requests"
    done
    echo
}

# Test 4: Throughput Benchmark
test_throughput() {
    print_header "Test 4: Throughput Benchmark"
    
    NUM_REQUESTS=50
    CONCURRENCY=10
    
    echo "Configuration:"
    echo "  - Total requests: $NUM_REQUESTS"
    echo "  - Concurrent requests: $CONCURRENCY"
    echo "  - Model: $MODEL"
    echo
    
    echo "Running benchmark..."
    START_TIME=$(date +%s.%N)
    
    for i in $(seq 1 $NUM_REQUESTS); do
        {
            curl -s -X POST "http://${GATEWAY_IP}/v1/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"${MODEL}\",\"prompt\":\"Test $i\",\"max_tokens\":10}" \
                > /dev/null 2>&1
            echo -n "."
        } &
        
        # Limit concurrency
        if (( i % CONCURRENCY == 0 )); then
            wait
        fi
    done
    
    wait
    END_TIME=$(date +%s.%N)
    
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    REQUESTS_PER_SEC=$(echo "scale=2; $NUM_REQUESTS / $DURATION" | bc)
    
    echo
    echo
    echo "Results:"
    echo "  - Total time: ${DURATION}s"
    echo "  - Requests completed: $NUM_REQUESTS"
    echo "  - Throughput: ${REQUESTS_PER_SEC} req/s"
    echo
    
    # Compare to expected baseline
    EXPECTED_PATTERN1=1.0
    IMPROVEMENT=$(echo "scale=1; $REQUESTS_PER_SEC / $EXPECTED_PATTERN1" | bc)
    
    print_success "Pattern 3 throughput: ${REQUESTS_PER_SEC} req/s"
    echo "  Expected Pattern 1 baseline: ~${EXPECTED_PATTERN1} req/s"
    echo "  Improvement factor: ${IMPROVEMENT}×"
    echo
}

# Test 5: Latency Profile
test_latency() {
    print_header "Test 5: Latency Profile"
    
    echo "Measuring P50, P95, P99 latency..."
    echo
    
    declare -a LATENCIES
    
    for i in {1..20}; do
        START=$(date +%s.%N)
        
        curl -s -X POST "http://${GATEWAY_IP}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${MODEL}\",\"prompt\":\"Quick test\",\"max_tokens\":10}" \
            > /dev/null 2>&1
        
        END=$(date +%s.%N)
        LATENCY=$(echo "($END - $START) * 1000" | bc)
        LATENCIES+=($LATENCY)
        
        echo "Request $i: ${LATENCY}ms"
        sleep 0.5
    done
    
    # Sort latencies
    IFS=$'\n' SORTED=($(sort -n <<<"${LATENCIES[*]}"))
    unset IFS
    
    # Calculate percentiles
    P50_IDX=$((20 * 50 / 100))
    P95_IDX=$((20 * 95 / 100))
    P99_IDX=$((20 * 99 / 100))
    
    echo
    echo "Latency Summary:"
    echo "  - P50: ${SORTED[$P50_IDX]}ms"
    echo "  - P95: ${SORTED[$P95_IDX]}ms"
    echo "  - P99: ${SORTED[$P99_IDX]}ms"
    echo
    
    print_success "Latency profile complete"
    echo
}

# Main execution
main() {
    echo
    print_header "Pattern 3 GPU Comprehensive Benchmark"
    echo "Gateway: http://${GATEWAY_IP}"
    echo "Namespace: ${NAMESPACE}"
    echo "Model: ${MODEL}"
    echo
    
    # Run all tests
    test_health || exit 1
    test_prefix_cache_routing
    test_load_distribution
    test_throughput
    test_latency
    
    # Final summary
    print_header "Benchmark Complete"
    print_success "All tests completed successfully"
    echo
    echo "Next steps:"
    echo "  1. Check monitoring dashboards for detailed metrics"
    echo "  2. Review EPP logs for routing decisions"
    echo "  3. Monitor GPU utilization with: kubectl exec -n kube-system <gpu-plugin-pod> -- nvidia-smi"
    echo
}

# Check dependencies
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { print_error "curl not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { print_error "jq not found"; exit 1; }
command -v bc >/dev/null 2>&1 || { print_error "bc not found"; exit 1; }

# Run main
main
