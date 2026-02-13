#!/bin/bash
set -e

# Pattern 3 Basic Functionality Test
# Tests health, models, completions, and chat completions endpoints

echo "========================================"
echo "Pattern 3: Basic Functionality Test"
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

# Test 1: Health check
echo "Test 1: Health check"
echo "--------------------"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
BODY=$(echo "$HEALTH_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Health check passed"
  echo "Response: $BODY"
else
  echo "❌ Health check failed (HTTP $HTTP_CODE)"
  echo "Response: $BODY"
  exit 1
fi
echo ""

# Test 2: Models list
echo "Test 2: Models list"
echo "-------------------"
MODELS_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/v1/models")
HTTP_CODE=$(echo "$MODELS_RESPONSE" | tail -n1)
BODY=$(echo "$MODELS_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Models list passed"
  echo "Response: $BODY" | jq '.'
else
  echo "❌ Models list failed (HTTP $HTTP_CODE)"
  echo "Response: $BODY"
  exit 1
fi
echo ""

# Test 3: Completion endpoint
echo "Test 3: Completion endpoint"
echo "---------------------------"
COMPLETION_REQUEST='{
  "model": "/mnt/models",
  "prompt": "The capital of France is",
  "max_tokens": 5,
  "temperature": 0.0
}'

COMPLETION_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d "$COMPLETION_REQUEST")
HTTP_CODE=$(echo "$COMPLETION_RESPONSE" | tail -n1)
BODY=$(echo "$COMPLETION_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Completion passed"
  echo "Response: $BODY" | jq '.'
else
  echo "❌ Completion failed (HTTP $HTTP_CODE)"
  echo "Response: $BODY"
  exit 1
fi
echo ""

# Test 4: Chat completion endpoint
echo "Test 4: Chat completion endpoint"
echo "--------------------------------"
CHAT_REQUEST='{
  "model": "/mnt/models",
  "messages": [
    {"role": "user", "content": "What is the capital of France?"}
  ],
  "max_tokens": 10,
  "temperature": 0.0
}'

CHAT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$CHAT_REQUEST")
HTTP_CODE=$(echo "$CHAT_RESPONSE" | tail -n1)
BODY=$(echo "$CHAT_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Chat completion passed"
  echo "Response: $BODY" | jq '.'
else
  echo "❌ Chat completion failed (HTTP $HTTP_CODE)"
  echo "Response: $BODY"
  exit 1
fi
echo ""

# Test 5: Verify 3 replicas running
echo "Test 5: Verify 3 replicas running"
echo "---------------------------------"
POD_COUNT=$(kubectl get pods -n llm-d-inference-scheduling \
  -l app.kubernetes.io/name=qwen2-3b-pattern3,kserve.io/component=workload \
  --field-selector=status.phase=Running \
  -o json | jq '.items | length')

if [ "$POD_COUNT" = "3" ]; then
  echo "✅ All 3 replicas running"
  kubectl get pods -n llm-d-inference-scheduling \
    -l app.kubernetes.io/name=qwen2-3b-pattern3,kserve.io/component=workload
else
  echo "❌ Expected 3 replicas, found $POD_COUNT"
  kubectl get pods -n llm-d-inference-scheduling \
    -l app.kubernetes.io/name=qwen2-3b-pattern3
  exit 1
fi
echo ""

echo "========================================"
echo "✅ All tests passed!"
echo "========================================"
