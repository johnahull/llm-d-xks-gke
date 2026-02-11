#!/bin/bash
# API Test Script for Istio + llm-d Pattern 1
# Tests basic functionality of deployed model

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
MODEL_NAME=${MODEL_NAME:-qwen2-3b-pattern1}

# Get Gateway IP
GATEWAY_IP=${GATEWAY_IP:-$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)}

if [ -z "$GATEWAY_IP" ]; then
  echo -e "${RED}ERROR: Could not determine Gateway IP${NC}"
  echo "Please set GATEWAY_IP environment variable or ensure Gateway is deployed"
  exit 1
fi

BASE_URL="http://${GATEWAY_IP}/llm-d-inference-scheduling/${MODEL_NAME}"

echo "========================================="
echo "API Test Suite for Pattern 1"
echo "========================================="
echo "Gateway IP: $GATEWAY_IP"
echo "Base URL: $BASE_URL"
echo "Namespace: $NAMESPACE"
echo "Model: $MODEL_NAME"
echo "========================================="
echo ""

# Test 1: Health Check
echo -e "${YELLOW}Test 1: Health Check${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Health check passed (HTTP $HTTP_CODE)${NC}"
else
  echo -e "${RED}✗ Health check failed (HTTP $HTTP_CODE)${NC}"
  exit 1
fi
echo ""

# Test 2: List Models
echo -e "${YELLOW}Test 2: List Models${NC}"
RESPONSE=$(curl -s ${BASE_URL}/v1/models)
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
if echo "$RESPONSE" | grep -q "Qwen"; then
  echo -e "${GREEN}✓ List models passed${NC}"
else
  echo -e "${RED}✗ List models failed${NC}"
  exit 1
fi
echo ""

# Test 3: Text Completion
echo -e "${YELLOW}Test 3: Text Completion${NC}"
RESPONSE=$(curl -s -X POST ${BASE_URL}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }')

echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
if echo "$RESPONSE" | grep -q "choices"; then
  echo -e "${GREEN}✓ Text completion passed${NC}"

  # Extract generated text
  GENERATED=$(echo "$RESPONSE" | jq -r '.choices[0].text' 2>/dev/null || echo "")
  if [ -n "$GENERATED" ]; then
    echo -e "${GREEN}Generated text: $GENERATED${NC}"
  fi

  # Extract token usage
  TOKENS=$(echo "$RESPONSE" | jq -r '.usage.total_tokens' 2>/dev/null || echo "")
  if [ -n "$TOKENS" ]; then
    echo -e "${GREEN}Total tokens: $TOKENS${NC}"
  fi
else
  echo -e "${RED}✗ Text completion failed${NC}"
  exit 1
fi
echo ""

# Test 4: Chat Completion
echo -e "${YELLOW}Test 4: Chat Completion${NC}"
RESPONSE=$(curl -s -X POST ${BASE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "messages": [
      {"role": "user", "content": "What is Kubernetes?"}
    ],
    "max_tokens": 100
  }')

echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
if echo "$RESPONSE" | grep -q "choices"; then
  echo -e "${GREEN}✓ Chat completion passed${NC}"

  # Extract generated text
  GENERATED=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
  if [ -n "$GENERATED" ]; then
    echo -e "${GREEN}Generated response: $GENERATED${NC}"
  fi
else
  echo -e "${RED}✗ Chat completion failed${NC}"
  exit 1
fi
echo ""

# Test 5: Metrics (if available)
echo -e "${YELLOW}Test 5: Prometheus Metrics${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${BASE_URL}/metrics)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Metrics endpoint accessible (HTTP $HTTP_CODE)${NC}"

  # Show sample metrics
  echo "Sample metrics:"
  curl -s ${BASE_URL}/metrics | grep "vllm_" | head -5
else
  echo -e "${YELLOW}⚠ Metrics endpoint not accessible (HTTP $HTTP_CODE) - may not be exposed${NC}"
fi
echo ""

# Test 6: Prefix Cache Test (send similar requests)
echo -e "${YELLOW}Test 6: Prefix Cache Test (EPP Routing)${NC}"
echo "Sending 3 similar requests to test prefix caching..."

PROMPT="Explain Kubernetes in one sentence:"
for i in {1..3}; do
  echo -n "Request $i: "
  START=$(date +%s%N)
  RESPONSE=$(curl -s -X POST ${BASE_URL}/v1/completions \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"Qwen/Qwen2.5-3B-Instruct\",
      \"prompt\": \"$PROMPT\",
      \"max_tokens\": 30
    }")
  END=$(date +%s%N)
  LATENCY=$(( (END - START) / 1000000 ))

  if echo "$RESPONSE" | grep -q "choices"; then
    echo -e "${GREEN}✓ ${LATENCY}ms${NC}"
  else
    echo -e "${RED}✗ Failed${NC}"
  fi
done
echo -e "${YELLOW}Note: Requests 2-3 should be faster if prefix caching is working${NC}"
echo ""

# Summary
echo "========================================="
echo -e "${GREEN}All tests completed successfully!${NC}"
echo "========================================="
echo ""
echo "Next Steps:"
echo "1. Run benchmark tests: ./scripts/benchmark-cluster.sh"
echo "2. Check EPP scheduler logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=scheduler"
echo "3. Monitor metrics: kubectl port-forward -n $NAMESPACE svc/$MODEL_NAME 8000:8000"
echo ""
