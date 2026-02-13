# Pattern 3 Deployment Guide

## Prerequisites

### Required Infrastructure

- **GKE Cluster:** `llmd-istio-tpu-pattern1` (europe-west4-a)
- **Gateway:** `inference-gateway` in `opendatahub` namespace
- **Istio:** Red Hat OpenShift Service Mesh (sail-operator)
- **KServe:** v0.15+ with LLMInferenceService CRD support
- **cert-manager:** For TLS certificate issuance

### Required Secrets

```bash
# Namespace
export NAMESPACE=llm-d-inference-scheduling

# HuggingFace token
kubectl get secret hf-token -n $NAMESPACE
# Key: HF_TOKEN

# Red Hat pull secret
kubectl get secret redhat-pull-secret -n $NAMESPACE
# Type: kubernetes.io/dockerconfigjson
```

### TPU Quotas

Verify TPU quota in `ecoeng-llmd` project:

```bash
gcloud compute project-info describe --project=ecoeng-llmd | grep -A 5 TPU
```

Required:
- `TPU_V6E_PODSLICE`: At least 12 chips (3 nodes × 4 chips)
- Region: `europe-west4`

## Deployment Process

### Phase 1: Cleanup Pattern 1 (~5 min)

```bash
export NAMESPACE=llm-d-inference-scheduling

# 1. Delete Pattern 1 LLMInferenceService
kubectl delete llmisvc qwen2-3b-pattern1 -n $NAMESPACE

# KServe controller auto-cleans:
# - HTTPRoute (qwen2-3b-pattern1-kserve-route)
# - InferencePool (qwen2-3b-pattern1)
# - Deployment (qwen2-3b-pattern1-workload)
# - Service (qwen2-3b-pattern1-workload)
# - EPP Scheduler (qwen2-3b-pattern1-router-scheduler)

# 2. Delete Pattern 1 EnvoyFilter
kubectl delete envoyfilter inference-pool-route-body-forwarding -n opendatahub --ignore-not-found

# 3. Delete Pattern 1 NetworkPolicies
kubectl delete networkpolicy \
  allow-gateway-to-epp-scheduler \
  allow-gateway-to-vllm \
  allow-vllm-egress \
  allow-istio-control-plane \
  -n $NAMESPACE \
  --ignore-not-found

# 4. Verify cleanup
kubectl get llmisvc,httproute,inferencepool,deployment,service -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern1
# Expected: No resources found

# 5. Verify no pods running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern1
# Expected: No resources found
```

**Validation:**
```bash
# Ensure Gateway still exists (shared infrastructure)
kubectl get gateway inference-gateway -n opendatahub
# Expected: NAME=inference-gateway, CLASS=istio

# Ensure Istio control plane running
kubectl get pods -n istio-system
# Expected: istiod-* and istio-ingressgateway-* Running
```

### Phase 2: Scale TPU Node Pool (~10-15 min)

```bash
# 1. Get current node count
gcloud container node-pools describe tpu-v6e-pool \
  --cluster llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --format="value(initialNodeCount)"

# 2. Scale from 1 to 3 nodes
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 3 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# 3. Monitor node creation
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice -w

# Wait for all 3 nodes Ready (takes ~10-15 min):
# NAME                                    STATUS   ROLES    AGE
# tpu-node-pool-xyz-abc1                  Ready    <none>   15m
# tpu-node-pool-xyz-abc2                  Ready    <none>   2m
# tpu-node-pool-xyz-abc3                  Ready    <none>   2m
```

**Validation:**
```bash
# Verify 3 nodes with 4 chips each
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice \
  -o custom-columns=NAME:.metadata.name,TPU:.status.allocatable."google\.com/tpu",READY:.status.conditions[?\(@.type==\"Ready\"\)].status

# Expected output:
# NAME                        TPU   READY
# tpu-node-pool-xyz-abc1      4     True
# tpu-node-pool-xyz-abc2      4     True
# tpu-node-pool-xyz-abc3      4     True
```

### Phase 3: Deploy Pattern 3 LLMInferenceService (~10-15 min)

```bash
# 1. Apply LLMInferenceService
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/llmisvc-tpu-pattern3.yaml

# 2. Watch LLMInferenceService status
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE -w

# Wait for READY=True (~10-15 min):
# NAME                 READY   URL
# qwen2-3b-pattern3    False
# qwen2-3b-pattern3    False
# qwen2-3b-pattern3    True    http://inference-gateway.opendatahub/llm-d-inference-scheduling/qwen2-3b-pattern3

# 3. Monitor pod creation
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3 -w

# Expected timeline:
# t=0s:    Pending (image pull)
# t=30s:   Init:0/1 (model download from HuggingFace)
# t=120s:  Init:0/1 (model download complete)
# t=180s:  PodInitializing (vLLM container starting)
# t=240s:  Running 0/2 (TPU initialization)
# t=600s:  Running 1/2 (XLA compilation)
# t=900s:  Running 2/2 (Ready!) ✅
```

**Validation:**
```bash
# Verify all 3 pods Running/Ready
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3,kserve.io/component=workload

# Expected: 3 pods, each 2/2 Running
# qwen2-3b-pattern3-workload-0   2/2   Running
# qwen2-3b-pattern3-workload-1   2/2   Running
# qwen2-3b-pattern3-workload-2   2/2   Running

# Verify HTTPRoute auto-created
kubectl get httproute qwen2-3b-pattern3-kserve-route -n $NAMESPACE

# Verify InferencePool auto-created
kubectl get inferencepool qwen2-3b-pattern3 -n $NAMESPACE

# Verify EPP scheduler deployed
kubectl get deployment qwen2-3b-pattern3-router-scheduler -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=router-scheduler

# Check EPP logs for scorer weights
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=router-scheduler --tail=50 | grep scorerWeights
# Expected: {"prefix-cache-scorer":3.0,"queue-scorer":1.0,"kv-cache-utilization-scorer":1.0}
```

### Phase 4: Apply EnvoyFilter (~1 min)

**CRITICAL:** Apply **after** LLMInferenceService is Ready (route names must exist)

```bash
# 1. Verify HTTPRoute exists
kubectl get httproute qwen2-3b-pattern3-kserve-route -n $NAMESPACE -o yaml | grep "name:"
# Expected: llm-d-inference-scheduling.qwen2-3b-pattern3-kserve-route.0
#           llm-d-inference-scheduling.qwen2-3b-pattern3-kserve-route.1

# 2. Apply EnvoyFilter
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/envoyfilter-route-extproc-body.yaml

# 3. Verify EnvoyFilter created
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub
```

**Validation:**
```bash
# Test that POST bodies are forwarded (EnvoyFilter working)
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"Test","max_tokens":5}'

# Expected: {"choices":[{"text":"..."}]}
# NOT: "prompt is required"
```

### Phase 5: Apply NetworkPolicies (~1 min)

```bash
# 1. Apply all NetworkPolicies
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching/manifests/networkpolicies/

# 2. Verify policies created
kubectl get networkpolicy -n $NAMESPACE

# Expected:
# allow-gateway-to-epp-scheduler-pattern3
# allow-gateway-to-vllm-pattern3
# allow-vllm-egress-pattern3
# allow-istio-control-plane-pattern3
```

**Validation:**
```bash
# Test that Gateway can reach vLLM (NetworkPolicy allowing)
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health
# Expected: {"status":"ok"}

# Test that EPP can reach vLLM metrics
kubectl exec -n $NAMESPACE deployment/qwen2-3b-pattern3-router-scheduler -- \
  curl -k -s https://qwen2-3b-pattern3-workload-0.$NAMESPACE.svc.cluster.local:8000/metrics | head -20
# Expected: vLLM Prometheus metrics
```

### Phase 6: Verification (~5 min)

```bash
# Get Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"

# Test 1: Health check
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health
# Expected: {"status":"ok"}

# Test 2: Models list
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/models
# Expected: {"object":"list","data":[{"id":"/mnt/models",...}]}

# Test 3: Completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"The capital of France is","max_tokens":5}'
# Expected: {"choices":[{"text":" Paris"}]}

# Test 4: Chat completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":10}'
# Expected: {"choices":[{"message":{"content":"4"}}]}

# Test 5: Run test suite
cd /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching
./scripts/test-cluster.sh
# Expected: All tests pass ✅
```

## Post-Deployment Validation

### Functional Tests

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching

# 1. Basic functionality
./scripts/test-cluster.sh

# 2. Prefix-cache routing
./scripts/verify-cache-routing.sh

# 3. Performance benchmark
./scripts/benchmark-cluster.sh
```

### Monitoring

```bash
# View EPP logs
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler -f

# View vLLM logs (replica 0)
kubectl logs -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c main -f

# View Istio sidecar logs (replica 0)
kubectl logs -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c istio-proxy -f

# Check vLLM metrics
kubectl exec -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -- \
  curl -k https://localhost:8000/metrics | grep vllm_

# Check cache hit rates
kubectl exec -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -- \
  curl -k https://localhost:8000/metrics | grep -E "cache_hit|cache_miss"
```

## Troubleshooting Common Issues

### Issue 1: Pods Stuck in Pending

**Symptoms:**
```
qwen2-3b-pattern3-workload-0   0/2   Pending
```

**Diagnosis:**
```bash
kubectl describe pod qwen2-3b-pattern3-workload-0 -n llm-d-inference-scheduling
# Look for Events section
```

**Common causes:**
1. Insufficient TPU nodes (need 3 nodes)
2. TPU node not Ready
3. Image pull error (check secret)

**Fix:**
```bash
# Scale node pool
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 3 \
  --zone europe-west4-a --project ecoeng-llmd --quiet

# Verify secrets
kubectl get secret redhat-pull-secret hf-token -n llm-d-inference-scheduling
```

### Issue 2: POST Body Lost

**Symptoms:**
```
{"error":"prompt is required"}
```

**Diagnosis:**
```bash
# Check EnvoyFilter exists
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub

# Check route names
kubectl get httproute qwen2-3b-pattern3-kserve-route -n llm-d-inference-scheduling -o yaml
```

**Fix:**
```bash
# Re-apply EnvoyFilter
kubectl apply -f manifests/envoyfilter-route-extproc-body.yaml
```

### Issue 3: Requests Not Distributing

**Symptoms:**
- All requests go to one replica
- Other replicas idle

**Diagnosis:**
```bash
# Check EPP logs
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler

# Verify NetworkPolicy
kubectl describe networkpolicy allow-gateway-to-epp-scheduler-pattern3 -n llm-d-inference-scheduling
```

**Fix:**
```bash
# Ensure NetworkPolicy allows EPP → vLLM metrics
kubectl apply -f manifests/networkpolicies/allow-epp-scheduler.yaml
```

## Cleanup Options

### Option 1: Scale to Zero (Preserve Config)

```bash
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 0 \
  --zone europe-west4-a --project ecoeng-llmd --quiet

# Cost: ~$6/day (CPU nodes only)
```

### Option 2: Restore Pattern 1

```bash
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 1 \
  --zone europe-west4-a --project ecoeng-llmd --quiet

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

- Review architecture: [docs/architecture.md](./architecture.md)
- Troubleshooting guide: [docs/troubleshooting.md](./troubleshooting.md)
- Compare with Gateway API Pattern 3: `/home/jhull/devel/llm-d-xks-gke/deployments/gateway-api/pattern3-caching/`
- Production hardening checklist: See [README.md](../README.md) "PoC Scope" section
