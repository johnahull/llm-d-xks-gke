# Pattern 3 Troubleshooting Guide

## Diagnostic Commands

### Quick Status Check

```bash
export NAMESPACE=llm-d-inference-scheduling

# 1. Check LLMInferenceService status
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE

# 2. Check pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# 3. Check HTTPRoute and InferencePool
kubectl get httproute,inferencepool -n $NAMESPACE

# 4. Check Gateway
kubectl get gateway inference-gateway -n opendatahub

# 5. Check EnvoyFilter
kubectl get envoyfilter -n opendatahub

# 6. Check NetworkPolicies
kubectl get networkpolicy -n $NAMESPACE
```

### Pod-Level Diagnostics

```bash
# Get pod names
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3 -o name

# Describe pod (events, status)
kubectl describe pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE

# View main container logs
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c main --tail=100

# View Istio sidecar logs
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c istio-proxy --tail=100

# View init container logs (model download)
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c storage-initializer

# Exec into pod
kubectl exec -it qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c main -- /bin/bash
```

## Common Issues

### Issue 1: Pods Stuck in Pending

**Symptoms:**
```
qwen2-3b-pattern3-workload-0   0/2   Pending   0   5m
qwen2-3b-pattern3-workload-1   0/2   Pending   0   5m
qwen2-3b-pattern3-workload-2   0/2   Pending   0   5m
```

**Root Causes:**

#### 1a. Insufficient TPU Nodes

**Diagnosis:**
```bash
# Check node count
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice

# Check node pool size
gcloud container node-pools describe tpu-v6e-pool \
  --cluster llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --format="value(initialNodeCount)"
```

**Fix:**
```bash
# Scale to 3 nodes
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 3 \
  --zone europe-west4-a --project ecoeng-llmd --quiet
```

#### 1b. TPU Resource Not Available

**Diagnosis:**
```bash
kubectl describe pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE | grep -A 5 "Events:"
# Look for: "0/3 nodes are available: 3 Insufficient google.com/tpu"
```

**Fix:**
- Wait for nodes to become Ready (~10-15 min)
- Verify TPU quota in GCP console

#### 1c. Image Pull Error

**Diagnosis:**
```bash
kubectl describe pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE | grep -i "pull"
# Look for: "Failed to pull image" or "ErrImagePull"
```

**Fix:**
```bash
# Verify secret exists
kubectl get secret redhat-pull-secret -n $NAMESPACE

# Re-create secret if needed
kubectl create secret docker-registry redhat-pull-secret \
  --docker-server=registry.redhat.io \
  --docker-username=<username> \
  --docker-password=<password> \
  -n $NAMESPACE
```

#### 1d. Istio Sidecar Cannot Fetch Config

**Symptoms:**
```
Events:
  Warning  FailedCreatePodSandBox  istio-proxy container cannot connect to istiod
```

**Diagnosis:**
```bash
# Check NetworkPolicy for Istio control plane
kubectl get networkpolicy allow-istio-control-plane-pattern3 -n $NAMESPACE

# Check istiod running
kubectl get pods -n istio-system -l app=istiod
```

**Fix:**
```bash
# Apply Istio NetworkPolicy
kubectl apply -f manifests/networkpolicies/allow-istio.yaml

# Restart pods if needed
kubectl delete pod -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3
```

---

### Issue 2: Pods Stuck in Init:0/1

**Symptoms:**
```
qwen2-3b-pattern3-workload-0   0/2   Init:0/1   0   10m
```

**Root Cause:** Model download from HuggingFace failing or slow

**Diagnosis:**
```bash
# Check init container logs
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c storage-initializer

# Look for:
# - "403 Forbidden" → HF token invalid or model not accessible
# - "Connection timeout" → Network policy blocking egress
# - Slow download → Large model, wait longer
```

**Fix:**

#### 2a. Invalid HuggingFace Token

```bash
# Verify secret
kubectl get secret hf-token -n $NAMESPACE -o yaml | grep HF_TOKEN | base64 -d

# Update token if needed
kubectl create secret generic hf-token \
  --from-literal=HF_TOKEN=<your-token> \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl delete pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE
```

#### 2b. NetworkPolicy Blocking Egress

```bash
# Verify egress policy allows HuggingFace
kubectl get networkpolicy allow-vllm-egress-pattern3 -n $NAMESPACE -o yaml

# Should allow: egress: [{}]  (allow all for PoC)
```

---

### Issue 3: Pods Stuck in Running 0/2 or 1/2

**Symptoms:**
```
qwen2-3b-pattern3-workload-0   1/2   Running   0   15m
```

**Root Causes:**

#### 3a. vLLM Container Failing

**Diagnosis:**
```bash
# Check vLLM logs
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c main

# Look for:
# - "TPU initialization failed"
# - "Out of memory"
# - "Model loading failed"
```

**Fix:**
```bash
# Restart pod
kubectl delete pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE

# If OOM, check max-model-len
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE -o yaml | grep max-model-len
# Should be: --max-model-len=2048 (not larger)
```

#### 3b. Readiness Probe Failing

**Diagnosis:**
```bash
kubectl describe pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE | grep -A 10 "Readiness:"

# Look for: "Readiness probe failed: Get https://...:8000/v1/models"
```

**Fix:**
- Wait longer (~15 min for first XLA compilation)
- Check vLLM is serving HTTPS (not HTTP)

```bash
# Test from inside pod
kubectl exec -n $NAMESPACE qwen2-3b-pattern3-workload-0 -c main -- \
  curl -k https://localhost:8000/v1/models
```

#### 3c. Istio Sidecar Not Ready

**Diagnosis:**
```bash
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c istio-proxy --tail=50

# Look for: "Connection to istiod failed"
```

**Fix:**
```bash
# Verify Istio NetworkPolicy
kubectl apply -f manifests/networkpolicies/allow-istio.yaml

# Restart pod
kubectl delete pod qwen2-3b-pattern3-workload-0 -n $NAMESPACE
```

---

### Issue 4: POST Body Lost (Error: "prompt is required")

**Symptoms:**
```bash
curl -X POST http://$GATEWAY_IP/.../v1/completions -d '{"prompt":"test"}'
# Returns: {"error":"prompt is required"}
```

**Root Cause:** EnvoyFilter not applied or route names mismatched

**Diagnosis:**
```bash
# 1. Check EnvoyFilter exists
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub

# 2. Check route names in HTTPRoute
kubectl get httproute qwen2-3b-pattern3-kserve-route -n $NAMESPACE -o yaml | grep "name:"

# Expected:
# - llm-d-inference-scheduling.qwen2-3b-pattern3-kserve-route.0
# - llm-d-inference-scheduling.qwen2-3b-pattern3-kserve-route.1

# 3. Check EnvoyFilter route names match
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub -o yaml | grep "name:"
```

**Fix:**
```bash
# Re-apply EnvoyFilter
kubectl apply -f manifests/envoyfilter-route-extproc-body.yaml

# If route names don't match, update EnvoyFilter
# Edit manifests/envoyfilter-route-extproc-body.yaml
# Change: "llm-d-inference-scheduling.qwen2-3b-pattern3-kserve-route.0"
# To match actual route name from HTTPRoute
```

---

### Issue 5: Requests Not Distributing Across Replicas

**Symptoms:**
- All requests go to one replica (e.g., workload-0)
- Other replicas show 0% CPU usage

**Root Causes:**

#### 5a. Only One Pod Ready

**Diagnosis:**
```bash
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# Check: Are all 3 pods 2/2 Running?
```

**Fix:**
- Wait for all 3 pods to be Ready
- If stuck, see Issue 1-3 above

#### 5b. EPP Cannot Scrape Metrics

**Diagnosis:**
```bash
# Check EPP logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=router-scheduler --tail=100

# Look for: "Failed to scrape metrics from qwen2-3b-pattern3-workload-1"

# Test EPP → vLLM connectivity
kubectl exec -n $NAMESPACE deployment/qwen2-3b-pattern3-router-scheduler -- \
  curl -k -s https://qwen2-3b-pattern3-workload-0.$NAMESPACE.svc.cluster.local:8000/metrics
```

**Fix:**
```bash
# Verify NetworkPolicy allows EPP → vLLM:8000
kubectl describe networkpolicy allow-gateway-to-epp-scheduler-pattern3 -n $NAMESPACE | grep -A 10 "Egress:"

# Should allow: to: podSelector (app.kubernetes.io/name=qwen2-3b-pattern3), ports: 8000

# Re-apply if missing
kubectl apply -f manifests/networkpolicies/allow-epp-scheduler.yaml
```

---

### Issue 6: Cache Routing Not Working (Shared Prefixes → Different Replicas)

**Symptoms:**
- `./scripts/verify-cache-routing.sh` shows requests split across multiple replicas
- Low cache hit rate

**Root Causes:**

#### 6a. Prefix Caching Not Enabled

**Diagnosis:**
```bash
# Check vLLM args
kubectl logs qwen2-3b-pattern3-workload-0 -n $NAMESPACE -c main | grep "enable-prefix-caching"

# Should see: --enable-prefix-caching in startup args
```

**Fix:**
```bash
# Verify LLMInferenceService manifest
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE -o yaml | grep "enable-prefix-caching"

# If missing, edit and re-apply
kubectl edit llmisvc qwen2-3b-pattern3 -n $NAMESPACE
# Add: --enable-prefix-caching to args

# Or re-apply manifest
kubectl apply -f manifests/llmisvc-tpu-pattern3.yaml
```

#### 6b. EPP Scorer Weights Not Configured

**Diagnosis:**
```bash
# Check InferencePool for scorer weights
kubectl get inferencepool qwen2-3b-pattern3 -n $NAMESPACE -o yaml | grep -A 10 "scorerWeights"

# Expected:
# scorerWeights:
#   prefix-cache-scorer: 3.0
#   queue-scorer: 1.0
#   kv-cache-utilization-scorer: 1.0
```

**Fix:**
```bash
# If missing, verify LLMInferenceService spec
kubectl get llmisvc qwen2-3b-pattern3 -n $NAMESPACE -o yaml | grep -A 10 "scorerWeights"

# Re-apply if needed
kubectl apply -f manifests/llmisvc-tpu-pattern3.yaml

# Delete InferencePool to trigger recreation
kubectl delete inferencepool qwen2-3b-pattern3 -n $NAMESPACE
# KServe will auto-recreate with correct weights
```

---

### Issue 7: Gateway Unreachable (Connection Refused)

**Symptoms:**
```bash
curl http://$GATEWAY_IP/...
# Connection refused or timeout
```

**Diagnosis:**
```bash
# 1. Check Gateway has external IP
kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}'

# 2. Check Gateway pods running
kubectl get pods -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway

# 3. Check LoadBalancer service
kubectl get svc -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway
```

**Fix:**
```bash
# If no external IP, wait for LoadBalancer provisioning
kubectl get svc -n opendatahub -w

# If Gateway pods CrashLooping, check logs
kubectl logs -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway
```

---

### Issue 8: High Latency (p50 > 1000ms)

**Symptoms:**
- Requests take >1 second
- Expected: 500-600ms

**Root Causes:**

#### 8a. Cold Start (First Request)

**Diagnosis:**
- First request always slow (XLA compilation)
- Subsequent requests should be fast

**Fix:**
- Send warmup requests after deployment
- Not a bug, expected behavior

#### 8b. All Replicas Queued

**Diagnosis:**
```bash
# Check queue depth
kubectl exec -n $NAMESPACE qwen2-3b-pattern3-workload-0 -c main -- \
  curl -k https://localhost:8000/metrics | grep vllm_queue_length

# If vllm_queue_length > 5 on all replicas, system is overloaded
```

**Fix:**
- Reduce request rate
- Scale to more replicas (requires more TPU nodes)

---

### Issue 9: Low Throughput (<5 req/s)

**Symptoms:**
- Benchmarks show <5.0 req/s
- Expected: 5.4-5.7 req/s

**Diagnosis:**
```bash
# 1. Check all 3 replicas running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# 2. Check CPU/memory usage
kubectl top pods -n $NAMESPACE -l app.kubernetes.io/name=qwen2-3b-pattern3

# 3. Check vLLM metrics
kubectl exec -n $NAMESPACE qwen2-3b-pattern3-workload-0 -c main -- \
  curl -k https://localhost:8000/metrics | grep -E "queue|cache|tokens"
```

**Possible Causes:**
- Only 1-2 replicas running (see Issue 5)
- Network latency (EPP → vLLM)
- Model max_tokens too high (reduce to 10-50 for benchmarks)

---

## Debug Workflows

### Workflow 1: Deployment Stuck

```bash
# 1. Check LLMInferenceService status
kubectl describe llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

# 2. Check KServe controller logs
kubectl logs -n opendatahub -l app=kserve-controller

# 3. Check pod events
kubectl get events -n llm-d-inference-scheduling --sort-by='.lastTimestamp' | grep qwen2-3b-pattern3
```

### Workflow 2: Requests Failing

```bash
# 1. Test Gateway → HTTPRoute
curl -v http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health

# 2. Test directly to vLLM (bypass Gateway)
kubectl port-forward -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 8000:8000
curl -k https://localhost:8000/health

# 3. Check EPP logs
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler -f

# 4. Check Istio sidecar logs
kubectl logs -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c istio-proxy -f
```

### Workflow 3: Performance Issues

```bash
# 1. Check resource utilization
kubectl top pods -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3

# 2. Check vLLM metrics
kubectl exec -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c main -- \
  curl -k https://localhost:8000/metrics | grep -E "vllm_queue|cache_hit|tokens_per_second"

# 3. Run benchmark
cd /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching
./scripts/benchmark-cluster.sh
```

---

## Useful Commands Reference

### Logs

```bash
# EPP scheduler logs
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler -f

# vLLM logs (all replicas)
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3 -c main -f

# Istio sidecar logs (replica 0)
kubectl logs -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c istio-proxy -f

# Gateway logs
kubectl logs -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway -f
```

### Metrics

```bash
# vLLM metrics (replica 0)
kubectl exec -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c main -- \
  curl -k https://localhost:8000/metrics

# EPP metrics
kubectl exec -n llm-d-inference-scheduling deployment/qwen2-3b-pattern3-router-scheduler -- \
  curl http://localhost:9090/metrics

# Node resource usage
kubectl top nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice

# Pod resource usage
kubectl top pods -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3
```

### Network Testing

```bash
# Test Gateway → vLLM
curl -v http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health

# Test EPP → vLLM metrics
kubectl exec -n llm-d-inference-scheduling deployment/qwen2-3b-pattern3-router-scheduler -- \
  curl -k https://qwen2-3b-pattern3-workload-0.llm-d-inference-scheduling.svc.cluster.local:8000/metrics

# Test pod → HuggingFace
kubectl exec -n llm-d-inference-scheduling qwen2-3b-pattern3-workload-0 -c main -- \
  curl -I https://huggingface.co
```

---

## Getting Help

If issues persist after troubleshooting:

1. **Collect diagnostics:**
   ```bash
   kubectl get all,networkpolicy,envoyfilter,httproute,inferencepool -n llm-d-inference-scheduling -o yaml > pattern3-diagnostics.yaml
   kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3 --tail=500 > pattern3-logs.txt
   ```

2. **Review documentation:**
   - Architecture: `docs/architecture.md`
   - Deployment guide: `docs/deployment-guide.md`
   - Pattern 1 reference: `/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/FINAL-STATUS-AND-BENCHMARKS.md`

3. **Check Pattern 1 for comparison:**
   - Pattern 1 is the proven baseline
   - If Pattern 1 works but Pattern 3 doesn't, issue is likely in:
     - EPP scorer configuration
     - NetworkPolicy (EPP → multiple replicas)
     - EnvoyFilter route names
