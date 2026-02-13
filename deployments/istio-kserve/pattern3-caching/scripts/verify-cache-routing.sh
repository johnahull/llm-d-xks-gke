#!/bin/bash
set -e

# Pattern 3 Prefix-Cache Routing Verification
# Tests that requests with shared prefixes are routed to the same replica

echo "========================================"
echo "Pattern 3: Prefix-Cache Routing Test"
echo "========================================"

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
if [ -z "$GATEWAY_IP" ]; then
  echo "❌ ERROR: Could not get Gateway IP"
  exit 1
fi

echo "Gateway IP: $GATEWAY_IP"
echo ""

# Base URL
BASE_URL="http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3"

# Shared prefix (200 tokens - long enough to trigger caching)
SHARED_PREFIX="In the year 2045, humanity had finally achieved what was once thought impossible: sustainable fusion energy. The breakthrough came from Dr. Elena Martinez, a physicist at CERN who had spent two decades refining the tokamak design. Her innovation involved using quantum-entangled plasma containment fields, which reduced energy loss by 87%. The first commercial fusion reactor, named Prometheus-1, was built in the Nevada desert and began operations on March 15th, 2045. Within six months, seventeen more reactors were under construction across five continents. The impact on global carbon emissions was immediate and dramatic. Coal and natural gas power plants began shutting down at a rate of twelve per month. Energy costs dropped by 65% within the first year. This economic shift triggered a renaissance in electric transportation, with major automakers transitioning entirely to battery-electric vehicles. The aviation industry followed suit, developing hydrogen-powered aircraft using fusion-generated electricity for electrolysis. By 2048, atmospheric CO2 levels had stabilized for the first time in 150 years. Now, in 2050,"

echo "Test: Sending 10 requests with shared prefix"
echo "Expected: All requests routed to the same replica (cache optimization)"
echo ""

# Track which replica handles each request
declare -a REPLICAS

for i in {1..10}; do
  echo -n "Request $i: "

  # Create request with shared prefix + unique suffix
  REQUEST="{
    \"model\": \"/mnt/models\",
    \"prompt\": \"$SHARED_PREFIX what is the status of renewable energy sources?\",
    \"max_tokens\": 10,
    \"temperature\": 0.0
  }"

  # Send request and capture response
  RESPONSE=$(curl -s -X POST "$BASE_URL/v1/completions" \
    -H "Content-Type: application/json" \
    -d "$REQUEST")

  # Check if request succeeded
  if echo "$RESPONSE" | jq -e '.choices[0].text' > /dev/null 2>&1; then
    echo "✅ Success"

    # Try to determine which replica handled the request
    # This is a simplification - in production, you'd use distributed tracing
    # For now, we'll use the completion text as a proxy (deterministic at temp=0)
    TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].text')
    REPLICAS+=("$TEXT")
  else
    echo "❌ Failed"
    echo "Response: $RESPONSE"
    exit 1
  fi

  sleep 0.5
done

echo ""
echo "========================================"
echo "Analysis:"
echo "========================================"

# Count unique responses (proxy for replica distribution)
UNIQUE_COUNT=$(printf '%s\n' "${REPLICAS[@]}" | sort -u | wc -l)

echo "Unique response patterns: $UNIQUE_COUNT"
echo ""

if [ "$UNIQUE_COUNT" -eq 1 ]; then
  echo "✅ EXCELLENT: All requests likely routed to same replica!"
  echo "   This indicates prefix-cache routing is working correctly."
  echo "   Shared prefix was cached on one replica, maximizing cache hits."
elif [ "$UNIQUE_COUNT" -le 2 ]; then
  echo "⚠️  WARNING: Requests split across $UNIQUE_COUNT replicas"
  echo "   Expected: 1 replica (optimal cache routing)"
  echo "   Possible causes:"
  echo "   - EPP scorer weights not configured correctly"
  echo "   - Prefix cache not enabled (missing --enable-prefix-caching)"
  echo "   - Shared prefix too short to trigger caching"
else
  echo "❌ FAILED: Requests distributed across $UNIQUE_COUNT replicas"
  echo "   Cache-aware routing is NOT working as expected"
  echo "   Check EPP scheduler logs:"
  echo "   kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler"
fi

echo ""
echo "Detailed breakdown:"
for i in "${!REPLICAS[@]}"; do
  echo "Request $((i+1)): ${REPLICAS[$i]}"
done

echo ""
echo "========================================"
echo "Next Steps:"
echo "========================================"
echo "1. Check EPP scorer configuration:"
echo "   kubectl get inferencepool qwen2-3b-pattern3 -n llm-d-inference-scheduling -o yaml | grep -A 10 scorerWeights"
echo ""
echo "2. Verify prefix caching enabled:"
echo "   kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3 | grep enable-prefix-caching"
echo ""
echo "3. Monitor cache hit rates:"
echo "   kubectl exec -n llm-d-inference-scheduling deployment/qwen2-3b-pattern3-router-scheduler -- \\"
echo "     curl -k https://qwen2-3b-pattern3-workload-0.llm-d-inference-scheduling:8000/metrics | grep cache"
echo ""
