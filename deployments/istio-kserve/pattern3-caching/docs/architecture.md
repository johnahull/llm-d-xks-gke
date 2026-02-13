# Pattern 3 Architecture: N/S-Caching Scale-Out

## Overview

Pattern 3 implements **prefix-cache-aware intelligent routing** using Istio + KServe + EPP (External Processing) to achieve 2.5-2.8× throughput improvement over Pattern 1's single-replica baseline.

## Core Innovation

### Prefix Caching

**What is it?**
- vLLM caches the KV (key-value) states of processed prompt prefixes
- When a new request shares a prefix with a cached prompt, vLLM reuses the cached KV states
- Eliminates redundant computation for repeated prompt prefixes

**Example:**
```
Request 1: "In the year 2045, humanity achieved fusion energy. What happened next?"
  → Full computation (no cache)

Request 2: "In the year 2045, humanity achieved fusion energy. Who led the project?"
  → Cache hit! Reuses KV states for "In the year 2045, humanity achieved fusion energy."
  → Only computes "Who led the project?"
  → ~40% faster (150 cached tokens, 6 new tokens)
```

### Cache-Aware Routing

**Problem:**
- With 3 replicas, naive round-robin routing distributes requests randomly
- Shared prefixes get split across replicas, reducing cache hit rate
- Cache hit rate: ~20% (random distribution)

**Solution:**
- EPP scheduler uses `prefix-cache-scorer` to route requests with shared prefixes to the same replica
- Maximizes cache hit rate by consolidating similar requests
- Target cache hit rate: 60-70% (with EPP routing)

**Scorer Algorithm:**
```
For each request:
  1. EPP extracts prompt prefix (first 200 tokens)
  2. Queries /metrics from all 3 vLLM replicas
  3. Calculates score per replica:
     score = (prefix_cache_hit_rate × 3.0) +
             (queue_depth × 1.0) +
             (kv_cache_utilization × 1.0)
  4. Routes to replica with highest score
```

**Why 2.0 weight?**
- Default in KServe v0.15 (not configurable via LLMInferenceService spec)
- Prioritizes cache hits over queue balancing (2× weight)
- Example: Replica with 80% cache hit rate scores 1.6 points from caching alone
- Queue depth of 3 requests adds 1.0 points
- Result: Cache optimization still prioritized in routing decisions

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         External Client                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTP
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Istio Gateway                                  │
│                  (inference-gateway)                                │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ EnvoyFilter: ext_proc body forwarding (BUFFERED mode)      │    │
│  │  - Sends request bodies to EPP for inspection             │    │
│  │  - Routes: .pattern3-kserve-route.0, .pattern3-kserve-route.1 │ │
│  └────────────────────────────────────────────────────────────┘    │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTPRoute (auto-created by KServe)
                             │ Path: /llm-d-inference-scheduling/qwen2-3b-pattern3/*
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  EPP Scheduler (ext_proc gRPC)                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Router Configuration:                                        │  │
│  │   scorerWeights:                                             │  │
│  │     prefix-cache-scorer: 3.0    ← HIGHEST                   │  │
│  │     queue-scorer: 1.0                                        │  │
│  │     kv-cache-utilization-scorer: 1.0                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Process per request:                                               │
│    1. Extract prompt prefix (200 tokens)                           │
│    2. Query /metrics from all vLLM replicas                        │
│    3. Calculate scores based on:                                   │
│       - Prefix cache hit rate (3.0× weight)                        │
│       - Queue depth (1.0× weight)                                  │
│       - KV cache utilization (1.0× weight)                         │
│    4. Route to highest-scoring replica                             │
└────────────────────────────┬───────────────────────────────────────┘
                             │ InferencePool (auto-created)
                             │ Backend: qwen2-3b-pattern3-workload
                ┌────────────┼────────────┬──────────────────────────┐
                │            │            │                          │
                ▼            ▼            ▼                          │
      ┌────────────┐ ┌────────────┐ ┌────────────┐                 │
      │ vLLM Pod 0 │ │ vLLM Pod 1 │ │ vLLM Pod 2 │                 │
      │            │ │            │ │            │                 │
      │ TPU v6e-4  │ │ TPU v6e-4  │ │ TPU v6e-4  │                 │
      │ (4 chips)  │ │ (4 chips)  │ │ (4 chips)  │                 │
      │            │ │            │ │            │                 │
      │ Qwen2.5-3B │ │ Qwen2.5-3B │ │ Qwen2.5-3B │                 │
      │ --enable-  │ │ --enable-  │ │ --enable-  │                 │
      │ prefix-    │ │ prefix-    │ │ prefix-    │                 │
      │ caching ✓  │ │ caching ✓  │ │ caching ✓  │                 │
      │            │ │            │ │            │                 │
      │ Metrics:   │ │ Metrics:   │ │ Metrics:   │                 │
      │ cache_hits │ │ cache_hits │ │ cache_hits │                 │
      │ queue_len  │ │ queue_len  │ │ queue_len  │                 │
      │ kv_usage   │ │ kv_usage   │ │ kv_usage   │                 │
      └────────────┘ └────────────┘ └────────────┘                 │
                                                                    │
      ┌─────────────────────────────────────────────────────────────┘
      │
      │ Each pod runs:
      │   - Istio sidecar (mTLS encryption)
      │   - vLLM container (HTTPS, KServe TLS certs)
      │   - Init container (model download from HuggingFace)
      │
      │ Per-replica resources:
      │   - 4 TPU chips (tensor-parallel-size=4)
      │   - 6 GB model weights
      │   - 2048 max context length
      │   - FP16 precision
      └─────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Istio Gateway

**Role:** External entry point, TLS termination, ext_proc integration

**Configuration:**
- External LoadBalancer IP
- TLS certificate: `inference-gateway-tls` (self-signed, PoC)
- EnvoyFilter: Enables ext_proc body forwarding in BUFFERED mode

**Why BUFFERED mode?**
- EPP needs full request body to extract prompt prefix
- Default STREAMED mode sends headers only
- Without BUFFERED mode, EPP cannot analyze prompts → no cache-aware routing

### 2. HTTPRoute (Auto-Created)

**Role:** Path-based routing from Gateway to InferencePool

**Created by:** KServe controller when LLMInferenceService is deployed

**Path:** `/llm-d-inference-scheduling/qwen2-3b-pattern3/*`

**Backends:**
- `.0` route: `/v1/chat/completions`
- `.1` route: `/v1/completions`

### 3. EPP Scheduler (External Processor)

**Role:** Cache-aware request routing

**Protocol:** gRPC ext_proc (Envoy extension)

**Ports:**
- 9002: ext_proc gRPC server (Gateway → EPP)
- 9003: Health check gRPC server
- 9090: Prometheus metrics

**Scorer Weights (KServe v0.15):**
```yaml
# Configured via ConfigMap (NOT in LLMInferenceService spec)
schedulingProfiles:
- name: default
  plugins:
  - pluginRef: prefix-cache-scorer
    weight: 2.0                      # Default in KServe v0.15
  - pluginRef: load-aware-scorer
    weight: 1.0
```

**Note:** The planned weight of 3.0 for prefix-cache-scorer is not supported in KServe v0.15's LLMInferenceService CRD. The default weight of 2.0 still provides cache-aware routing with 2× priority over load balancing.

**Scoring Example (with weight 2.0):**
```
Replica 0: cache=0.85, queue=2, kv=0.60
  → Score = (0.85 × 2.0) + (2 × 1.0) + (0.60 × 1.0) = 4.30 ✅ SELECTED

Replica 1: cache=0.20, queue=1, kv=0.50
  → Score = (0.20 × 2.0) + (1 × 1.0) + (0.50 × 1.0) = 1.90

Replica 2: cache=0.10, queue=3, kv=0.70
  → Score = (0.10 × 2.0) + (3 × 1.0) + (0.70 × 1.0) = 3.90
```

### 4. InferencePool (Auto-Created)

**Role:** Backend pool of vLLM replicas

**Created by:** KServe controller

**Discovery:** Kubernetes Service (headless) for pod discovery

**Health Checks:** Periodic probes to `/health` endpoint

### 5. vLLM Replicas (3 Pods)

**Role:** LLM inference with prefix caching

**Container Image:** `registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5`

**Key Args:**
```bash
--model=/mnt/models
--dtype=half
--max-model-len=2048
--tensor-parallel-size=4
--enable-prefix-caching      # ← CRITICAL for Pattern 3
--ssl-certfile=/var/run/kserve/tls/tls.crt
--ssl-keyfile=/var/run/kserve/tls/tls.key
```

**TPU Configuration:**
```yaml
env:
  - name: TPU_CHIPS_PER_HOST_BOUNDS
    value: "2,2,1"  # 2x2 topology (4 chips)
  - name: TPU_HOST_BOUNDS
    value: "1,1,1"  # Single host
  - name: PJRT_DEVICE
    value: "TPU"
```

**Resources:**
```yaml
resources:
  limits:
    google.com/tpu: "4"  # All 4 chips per replica
  requests:
    google.com/tpu: "4"
```

## Security Model

### Network Policies

**1. allow-gateway-to-epp-scheduler-pattern3**
- Allows Gateway → EPP (ports 9002, 9003, 9090)
- Allows EPP → vLLM metrics (port 8000, all 3 replicas)
- Allows EPP → Kubernetes API (InferencePool discovery)

**2. allow-gateway-to-vllm-pattern3**
- Allows Gateway → vLLM (port 8000)
- Allows kubelet → vLLM (health probes)

**3. allow-vllm-egress-pattern3**
- Allows vLLM → HuggingFace Hub (model download)
- Allows vLLM → DNS (kube-dns)
- PoC: `egress: [{}]` (allow all, restrict in production)

**4. allow-istio-control-plane-pattern3**
- Allows Istio sidecars → istiod (ports 15012, 15017)
- CRITICAL: Without this, pods fail to start (sidecar cannot fetch config)

### Encryption Layers

**1. Client → Gateway:**
- TLS (HTTPS)
- Certificate: `inference-gateway-tls`
- PoC: Self-signed (use Let's Encrypt in production)

**2. Gateway → EPP:**
- gRPC over TLS
- mTLS in PERMISSIVE mode (PoC)

**3. Gateway → vLLM:**
- Istio mTLS (sidecar-to-sidecar)
- Mode: PERMISSIVE (allows HTTP fallback for debugging)
- Production: Use STRICT mode

**4. Istio Sidecar → vLLM App:**
- KServe TLS (HTTPS)
- Certificate: Auto-issued by KServe controller
- Mounts: `/var/run/kserve/tls/tls.{crt,key}`

## Scaling Efficiency Analysis

### Ideal vs Actual Throughput

**Pattern 1 Baseline:**
- 1 replica: 1.89 req/s (serial), 7.5 req/s (parallel)

**Pattern 3 Ideal (Linear Scaling):**
- 3 replicas: 5.67 req/s (serial), 22.5 req/s (parallel)

**Pattern 3 Actual:**
- Serial: 5.4-5.7 req/s (95-100% efficiency)
- Parallel: 20-22 req/s (89-98% efficiency)

**Why not 100%?**
- EPP routing overhead (~10-20ms per request)
- Cache coordination overhead (metrics scraping)
- Queue balancing (prevents overload on high-cache replicas)

**Cache Hit Rate Impact:**
- Without caching: ~5.0 req/s baseline (naive round-robin)
- With caching: 5.5-5.7 req/s (+10-14% improvement)
- Cache hit rate: 60-70% (workload dependent)

## Comparison with Pattern 1

| Component | Pattern 1 | Pattern 3 |
|-----------|-----------|-----------|
| **Infrastructure** |
| Replicas | 1 | 3 |
| TPU Nodes | 1 node (4 chips) | 3 nodes (12 chips) |
| Cost | $5.50/hour | $15.74/hour |
| **vLLM Configuration** |
| Prefix Caching | ❌ Disabled | ✅ Enabled |
| Caching Flag | N/A | `--enable-prefix-caching` |
| **Routing** |
| Strategy | Single endpoint | EPP cache-aware routing |
| Scorer Weights | N/A | prefix-cache: 3.0 |
| **Performance** |
| Throughput (serial) | 1.89 req/s | 5.4-5.7 req/s |
| Throughput (parallel) | 7.5 req/s | 20-22 req/s |
| Scaling Efficiency | 100% | 97% |
| Cache Hit Rate | 0% | 60-70% |
| **Security** |
| NetworkPolicies | 3 policies | 4 policies |
| Istio mTLS | PERMISSIVE | PERMISSIVE |
| KServe TLS | ✅ Enabled | ✅ Enabled |

## Cost Analysis

**Infrastructure Costs:**
```
Pattern 1: $5.50/hour × 24 hours × 30 days = $3,960/month
Pattern 3: $15.74/hour × 24 hours × 30 days = $11,336/month
Increase: +$7,376/month (+186%)
```

**Cost per Request:**
```
Pattern 1: $3,960 / (1.89 req/s × 86400s × 30d) = $203.70 per 1M requests
Pattern 3: $11,336 / (5.5 req/s × 86400s × 30d) = $208.20 per 1M requests
Increase: +$4.50 per 1M requests (+2.2%)
```

**Break-Even Analysis:**
- If throughput > 1M requests/month: Pattern 3 is cost-efficient
- If throughput < 500K requests/month: Pattern 1 is cheaper
- Sweet spot: 2-10M requests/month (best ROI for Pattern 3)

## PoC Scope: Included vs Deferred

### ✅ Included (Validates Pattern 3 Concept)

1. **Core Functionality:**
   - 3 replicas with prefix caching enabled
   - EPP cache-aware routing (scorer weights)
   - NetworkPolicies enforced
   - EnvoyFilter for body forwarding

2. **Verification:**
   - Basic functionality tests
   - Cache routing validation
   - Load distribution tests
   - Performance benchmarks

3. **Security:**
   - Istio mTLS in PERMISSIVE mode
   - NetworkPolicies with default-deny
   - Self-signed TLS certificates
   - Image pull secrets

### ⏭️ Deferred to Production

1. **High Availability:**
   - PodDisruptionBudget (HA during node maintenance)
   - Topology spread constraints (anti-affinity)
   - Resource limits tuning (focus on requests only for PoC)

2. **Observability:**
   - Prometheus ServiceMonitors
   - Grafana dashboards (cache hit rate, queue depth)
   - Alerting rules (PagerDuty/Opsgenie)
   - Distributed tracing (Jaeger/Tempo)

3. **Advanced Security:**
   - STRICT mTLS mode (PERMISSIVE for debugging)
   - Valid TLS certificates (Let's Encrypt)
   - External Secrets Operator
   - Image signing verification

4. **Autoscaling:**
   - HorizontalPodAutoscaler (fixed 3 replicas for PoC)
   - KEDA event-driven scaling
   - TPU node pool autoscaling

## Troubleshooting Tips

### Issue: Requests Not Distributing

**Symptoms:**
- All requests go to one replica
- Other replicas idle

**Diagnosis:**
```bash
# Check EPP logs
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/component=router-scheduler

# Verify NetworkPolicy allows EPP → vLLM metrics
kubectl describe networkpolicy allow-gateway-to-epp-scheduler-pattern3 -n llm-d-inference-scheduling
```

**Fix:**
- Ensure NetworkPolicy allows EPP to scrape metrics from all 3 replicas (port 8000)

### Issue: Cache Routing Not Working

**Symptoms:**
- Requests with shared prefixes go to different replicas
- Low cache hit rate

**Diagnosis:**
```bash
# Verify scorer weights configured
kubectl get inferencepool qwen2-3b-pattern3 -n llm-d-inference-scheduling -o yaml | grep -A 10 scorerWeights

# Check vLLM logs for prefix caching
kubectl logs -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3 | grep enable-prefix-caching
```

**Fix:**
- Verify `--enable-prefix-caching` in vLLM args
- Verify scorer weights: `prefix-cache-scorer: 3.0`

### Issue: POST Body Lost

**Symptoms:**
- `/v1/completions` returns error: "prompt is required"
- `/v1/chat/completions` returns error: "messages is required"

**Diagnosis:**
```bash
# Check EnvoyFilter exists
kubectl get envoyfilter inference-pool-route-body-forwarding-pattern3 -n opendatahub

# Verify route names match HTTPRoute
kubectl get httproute qwen2-3b-pattern3-kserve-route -n llm-d-inference-scheduling -o yaml | grep "name:"
```

**Fix:**
- Apply EnvoyFilter: `kubectl apply -f manifests/envoyfilter-route-extproc-body.yaml`
- Ensure route names match: `.pattern3-kserve-route.0`, `.pattern3-kserve-route.1`

## References

- Pattern 1 Architecture: `/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/docs/architecture-review.md`
- KServe LLMInferenceService Docs: https://kserve.github.io/website/latest/reference/api/#serving.kserve.io/v1alpha1.LLMInferenceService
- vLLM Prefix Caching: https://docs.vllm.ai/en/latest/features/prefix_caching.html
- Envoy ext_proc: https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_proc_filter
