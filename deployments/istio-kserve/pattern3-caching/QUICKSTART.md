# Pattern 3 Quickstart Guide

## Prerequisites Check

Before starting, verify:

```bash
# 1. Cluster exists
gcloud container clusters describe llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd

# 2. Get cluster credentials
gcloud container clusters get-credentials llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd

# 3. Verify namespace and secrets exist
kubectl get namespace llm-d-inference-scheduling
kubectl get secret hf-token redhat-pull-secret -n llm-d-inference-scheduling

# 4. Verify Gateway and Istio are running
kubectl get gateway inference-gateway -n opendatahub
kubectl get pods -n istio-system
```

## Deployment Steps

### Step 1: Delete Pattern 1 Deployment (~5 min)

```bash
export NAMESPACE=llm-d-inference-scheduling

# Delete Pattern 1 LLMInferenceService (auto-cleans HTTPRoute, InferencePool, EPP)
kubectl delete llmisvc qwen2-3b-pattern1 -n $NAMESPACE

# Delete Pattern 1 EnvoyFilter (if exists)
kubectl delete envoyfilter inference-pool-route-body-forwarding -n opendatahub

# Delete Pattern 1 NetworkPolicies (if exist)
kubectl delete networkpolicy \
  allow-gateway-to-epp-scheduler \
  allow-gateway-to-vllm \
  allow-vllm-egress \
  allow-istio-control-plane \
  -n $NAMESPACE

# Verify cleanup
kubectl get llmisvc,httproute,inferencepool -n $NAMESPACE
# Expected: No resources found
```

### Step 2: Scale TPU Node Pool (~10-15 min)

```bash
# Scale from 1 to 3 nodes
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 3 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Wait for all 3 nodes to be Ready
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice -w

# Verify 3 nodes with 4 chips each
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice \
  -o custom-columns=NAME:.metadata.name,TPU:.status.allocatable."google\.com/tpu"
# Expected output:
# NAME                                    TPU
# tpu-node-1                              4
# tpu-node-2                              4
# tpu-node-3                              4
```

### Step 3: Deploy Pattern 3 LLMInferenceService (~10-15 min)

```bash
# Apply LLMInferenceService manifest
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/llmisvc-tpu-pattern3.yaml

# Watch deployment progress
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE -w
# Wait for READY = True (~10-15 min)

# Monitor pod creation
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3 -w

# Check logs for any errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3 -f
```

**Timeline:**
- t=0s: LLMInferenceService created
- t=30s: KServe creates Deployment, HTTPRoute, InferencePool, EPP scheduler
- t=120s: 3 vLLM pods pull image + download model (parallel)
- t=600s: TPU initialization + XLA compilation
- t=900s: All 3 pods Running/Ready ✅

### Step 4: Apply EnvoyFilter (~1 min)

**CRITICAL:** Apply **after** LLMInferenceService (route names must exist first)

```bash
# Apply EnvoyFilter for ext_proc body forwarding
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/envoyfilter-route-extproc-body.yaml

# Verify EnvoyFilter created
kubectl get envoyfilter -n opendatahub
# Expected: inference-pool-route-body-forwarding-pattern3
```

### Step 5: Apply NetworkPolicies (~1 min)

```bash
# Apply all NetworkPolicies
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/networkpolicies/

# Verify NetworkPolicies created
kubectl get networkpolicy -n $NAMESPACE
# Expected:
# allow-gateway-to-epp-scheduler-pattern3
# allow-gateway-to-vllm-pattern3
# allow-vllm-egress-pattern3
# allow-istio-control-plane-pattern3
```

### Step 6: Verify Deployment (~5 min)

```bash
# Get Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"

# Test health endpoint
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health
# Expected: {"status": "ok"}

# Test models endpoint
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/models
# Expected: {"object":"list","data":[{"id":"/mnt/models",...}]}

# Test inference (verify body forwarding works)
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"The capital of France is","max_tokens":5}'
# Expected: {"choices":[{"text":" Paris"}]}

# Verify all 3 replicas running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3,kserve.io/component=workload
# Expected: 3 pods in Running state (2/2 containers)

# Check EPP scheduler configuration
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=router-scheduler --tail=50
# Look for: "Scorers: [prefix-cache-scorer/prefix-cache-scorer: 2"
# Note: KServe v0.15 uses default weights (2.0) configured via ConfigMap, not LLMInferenceService spec

# Verify HTTPRoute and InferencePool auto-created
kubectl get httproute -n $NAMESPACE
kubectl get inferencepool -n $NAMESPACE
# Expected: qwen2-3b-pattern3-kserve-route, qwen2-3b-pattern3
```

## Verification Tests

### Test 1: Basic Functionality

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching
./scripts/test-cluster.sh
```

Expected output:
```
✅ Health check: OK
✅ Models list: OK
✅ Completion: OK
✅ Chat completion: OK
```

### Test 2: Prefix-Cache Routing

```bash
./scripts/verify-cache-routing.sh
```

Expected output:
```
Sending 10 requests with shared 200-token prefix...
Request 1 → Replica 2 (score: 3.2)
Request 2 → Replica 2 (score: 5.8, cache hit!)
Request 3 → Replica 2 (score: 5.8, cache hit!)
...
✅ All 10 requests routed to same replica
```

### Test 3: Load Distribution

```bash
# Send 15 unique requests (no shared prefix)
for i in {1..15}; do
  curl -s -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"/mnt/models\",\"prompt\":\"Random $i\",\"max_tokens\":10}" &
done
wait

# Check pod logs to see request distribution
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3 --tail=50 | grep "Received request"
# Expected: Roughly even distribution across 3 replicas
```

### Test 4: Performance Benchmark

```bash
./scripts/benchmark-cluster.sh
```

Expected metrics:

| Metric | Target |
|--------|--------|
| Throughput (serial) | 5.4-5.7 req/s |
| Throughput (batched) | 20-22 req/s |
| TTFT p50 | 510-530ms |
| Success Rate | 100% |
| Scaling Efficiency | 97% |

## Troubleshooting

### Issue: Only 1-2 pods running

**Cause:** Insufficient TPU nodes

**Solution:**
```bash
# Verify node pool scaled to 3 nodes
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
# Should show 3 nodes

# If not, scale again
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 3 \
  --zone europe-west4-a --project ecoeng-llmd --quiet
```

### Issue: Requests not distributing

**Cause:** Only 1 pod Ready, or NetworkPolicy blocking EPP→vLLM

**Solution:**
```bash
# Verify all 3 pods Ready
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# Check NetworkPolicy allows EPP to scrape metrics
kubectl describe networkpolicy allow-gateway-to-epp-scheduler-pattern3 -n $NAMESPACE
# Should allow egress to port 8000

# Test EPP can reach vLLM metrics
kubectl exec -n $NAMESPACE deployment/qwen2-3b-pattern3-router-scheduler -- \
  curl -k https://qwen2-3b-pattern3-workload-0.llm-d-inference-scheduling:8000/metrics
```

### Issue: POST body lost

**Cause:** EnvoyFilter not applied or wrong route names

**Solution:**
```bash
# Verify EnvoyFilter exists
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub

# Check route names in HTTPRoute
kubectl get httproute qwen2-3b-pattern3-kserve-route -n $NAMESPACE -o yaml | grep -A 5 "rules:"

# Re-apply EnvoyFilter if needed
kubectl apply -f manifests/envoyfilter-route-extproc-body.yaml
```

### Issue: Pods stuck in Pending

**Cause:** Istio sidecar cannot fetch config (NetworkPolicy blocking)

**Solution:**
```bash
# Verify allow-istio NetworkPolicy exists
kubectl get networkpolicy allow-istio-control-plane-pattern3 -n $NAMESPACE

# Check pod events
kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# Re-apply NetworkPolicy if missing
kubectl apply -f manifests/networkpolicies/allow-istio.yaml
```

## Cleanup

### Option 1: Scale to Zero (Preserve Config)

```bash
# Delete LLMInferenceService (keeps manifests)
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

# Scale node pool to 0
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 0 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Cost: ~$6/day (CPU nodes only)
```

### Option 2: Restore Pattern 1

```bash
# Delete Pattern 3
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

# Scale to 1 node
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Deploy Pattern 1
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/manifests/llmisvc-tpu.yaml
```

### Option 3: Delete Entire Cluster

```bash
gcloud container clusters delete llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Cost: $0/day
```

## Next Steps

- Review architecture: `docs/architecture.md`
- Deep dive deployment: `docs/deployment-guide.md`
- Troubleshooting guide: `docs/troubleshooting.md`
- Compare with Gateway API Pattern 3: `/home/jhull/devel/llm-d-xks-gke/deployments/gateway-api/pattern3-caching/`

## Success Criteria Checklist

- ✅ All 3 vLLM pods Running/Ready (2/2 containers)
- ✅ EPP scheduler deployed with scorer weights configured
- ✅ HTTPRoute and InferencePool auto-created
- ✅ NetworkPolicies enforced (including allow-istio.yaml)
- ✅ Health endpoint returns 200 OK
- ✅ Inference requests succeed (POST body forwarding works)
- ✅ Prefix-cache routing verified (shared prompts → same replica)
- ✅ Load distribution works (unique prompts → balanced)
- ✅ Performance: 2.5-2.8× throughput improvement vs Pattern 1
- ✅ 100% success rate under load
