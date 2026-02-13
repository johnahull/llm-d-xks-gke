# Pattern 3: N/S-Caching Scale-Out (Istio + KServe)

## Overview

Pattern 3 demonstrates **prefix-cache-aware intelligent routing** with 3 replicas for 2.5-2.8× throughput improvement over Pattern 1 baseline.

**Key Features:**
- ✅ 3 replicas (12 TPU chips total) with `--enable-prefix-caching`
- ✅ EPP cache-aware routing (prefix-cache-scorer: 2.0 default in KServe v0.15)
- ✅ NetworkPolicies enforced (defense-in-depth security)
- ✅ EnvoyFilter for ext_proc body forwarding (validated in Pattern 1)
- ✅ Istio mTLS in PERMISSIVE mode (PoC-appropriate)

**Note on Scorer Weights:** KServe v0.15 does not support `scorerWeights` in LLMInferenceService spec. Weights are configured via ConfigMap with defaults: `prefix-cache-scorer: 2.0`, `load-aware-scorer: 1.0`. While lower than the planned 3.0, this still provides effective cache-aware routing.

**PoC Objectives:**
- Validate prefix caching with shared prompts
- Demonstrate cache-aware routing (requests with shared prefixes → same replica)
- Measure scaling efficiency (target: 97% with 3 replicas)
- Prove 2.5-2.8× throughput improvement vs Pattern 1

## Quick Start

See [QUICKSTART.md](./QUICKSTART.md) for step-by-step deployment instructions.

## Architecture

```
                                    ┌──────────────────────┐
                                    │  Istio Gateway       │
                                    │  (inference-gateway) │
                                    └──────────┬───────────┘
                                               │
                                               │ HTTPRoute (auto-created)
                                               ▼
                      ┌────────────────────────────────────────────┐
                      │        EPP Scheduler (ext_proc)            │
                      │  Cache-Aware Routing (prefix-cache-scorer) │
                      └────┬──────────────┬──────────────┬─────────┘
                           │              │              │
        ┌──────────────────┼──────────────┼──────────────┼──────────────────┐
        │                  │              │              │                  │
        │  InferencePool   │              │              │                  │
        │                  ▼              ▼              ▼                  │
        │         ┌────────────┐ ┌────────────┐ ┌────────────┐             │
        │         │  vLLM Pod  │ │  vLLM Pod  │ │  vLLM Pod  │             │
        │         │  (4 chips) │ │  (4 chips) │ │  (4 chips) │             │
        │         │  Prefix ✓  │ │  Prefix ✓  │ │  Prefix ✓  │             │
        │         └────────────┘ └────────────┘ └────────────┘             │
        └───────────────────────────────────────────────────────────────────┘
```

**Routing Algorithm:**
```
For each request:
  1. EPP queries /metrics from all 3 replicas
  2. Calculates score = (prefix_cache_hit_rate × 3.0) + (queue_depth × 1.0) + (kv_cache_free × 1.0)
  3. Routes to replica with highest score (maximizes cache hits)
```

## Performance Targets

| Metric | Pattern 1 | Pattern 3 | Improvement |
|--------|-----------|-----------|-------------|
| Throughput (serial) | 1.89 req/s | 5.4-5.7 req/s | **2.8-3.0×** |
| Throughput (batched) | 7.5 req/s | 20-22 req/s | **2.7-2.9×** |
| TTFT p50 | 512ms | 510-530ms | Similar |
| Scaling Efficiency | 100% | **97%** | -3% |
| Success Rate | 100% | 100% | Same |

## Cost Analysis

**Infrastructure:**
- 3 TPU nodes × 4 chips = 12 chips total
- Cost: $15.74/hour = $11,336/month
- Pattern 1 cost: $5.50/hour = $3,960/month

**Cost per Request:**
- Pattern 1: $203.70 per 1M requests
- Pattern 3: $208.20 per 1M requests (+2.2%)

**Conclusion:** 2.8× higher throughput for 2.9× higher infrastructure cost = similar cost efficiency at scale.

## Directory Structure

```
pattern3-caching/
├── README.md                          # This file
├── QUICKSTART.md                      # Step-by-step deployment guide
├── manifests/
│   ├── llmisvc-tpu-pattern3.yaml     # 3 replicas with prefix caching
│   ├── envoyfilter-route-extproc-body.yaml
│   └── networkpolicies/
│       ├── allow-epp-scheduler.yaml   # EPP → vLLM metrics (all 3 replicas)
│       ├── allow-gateway-to-vllm.yaml # Gateway → vLLM
│       ├── allow-vllm-egress.yaml     # vLLM → HuggingFace/DNS
│       └── allow-istio.yaml           # Istio sidecar → control plane
├── docs/
│   ├── architecture.md                # Architecture deep dive
│   ├── deployment-guide.md            # Detailed deployment guide
│   └── troubleshooting.md             # Common issues and solutions
├── scripts/
│   ├── test-cluster.sh                # Basic functionality tests
│   ├── benchmark-cluster.sh           # Performance benchmarking
│   └── verify-cache-routing.sh        # Verify prefix cache routing
└── benchmarks/
    └── results/                       # Benchmark results
```

## Prerequisites

- Existing GKE cluster: `llmd-istio-tpu-pattern1` (europe-west4-a)
- Pattern 1 deployment deleted (reuses same infrastructure)
- TPU node pool scaled to 3 nodes
- Namespace: `llm-d-inference-scheduling` (reuses secrets)

## Key Differences from Pattern 1

| Component | Pattern 1 | Pattern 3 |
|-----------|-----------|-----------|
| Replicas | 1 | 3 |
| vLLM Args | No caching | `--enable-prefix-caching` |
| EPP Scorer | Default weights | `prefix-cache-scorer: 2.0` (ConfigMap) |
| NetworkPolicy | 1 replica | Allow EPP → 3 replicas |
| TPU Nodes | 1 node (4 chips) | 3 nodes (12 chips) |

**Note:** Scorer weights are configured via ConfigMap in KServe v0.15, not via LLMInferenceService YAML.

## Deployment Steps

1. **Delete Pattern 1** (5 min)
2. **Scale TPU node pool** to 3 nodes (10-15 min)
3. **Deploy LLMInferenceService** (10-15 min)
4. **Apply EnvoyFilter** (1 min)
5. **Apply NetworkPolicies** (1 min)
6. **Verify deployment** (5 min)

**Total time:** ~40-50 minutes

See [QUICKSTART.md](./QUICKSTART.md) for detailed commands.

## Verification

```bash
# Get Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

# Test health
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/health

# Test inference
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"The capital of France is","max_tokens":5}'

# Verify all 3 pods running
kubectl get pods -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern3
```

## Testing Scripts

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/istio-kserve/pattern3-caching

# Basic functionality
./scripts/test-cluster.sh

# Verify cache routing (shared prompts → same replica)
./scripts/verify-cache-routing.sh

# Performance benchmarking
./scripts/benchmark-cluster.sh
```

## PoC Scope

### ✅ Included (Validates Pattern 3 Concept)

- Core functionality (3 replicas, prefix caching, cache-aware routing)
- NetworkPolicies enforced
- EnvoyFilter for body forwarding
- Verification tests
- Performance benchmarks

### ⏭️ Deferred to Production

- PodDisruptionBudget (HA during maintenance)
- ServiceMonitors + Grafana dashboards
- STRICT mTLS mode (PERMISSIVE for PoC)
- Resource limits tuning
- HorizontalPodAutoscaler (fixed 3 replicas)

## Cleanup

**Option 1: Scale to zero (preserve config)**
```bash
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 0 --zone europe-west4-a --quiet
```

**Option 2: Restore Pattern 1**
```bash
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool --num-nodes 1 --zone europe-west4-a --quiet
kubectl apply -f /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/manifests/llmisvc-tpu.yaml
```

## References

- Pattern 1 Deployment: `/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/`
- Gateway API Pattern 3: `/home/jhull/devel/llm-d-xks-gke/deployments/gateway-api/pattern3-caching/`
- Benchmarking Guide: `/home/jhull/devel/llm-d-xks-gke/docs/benchmarking.md`

## Support

For issues or questions:
- Architecture review: `docs/architecture.md`
- Troubleshooting: `docs/troubleshooting.md`
- Pattern 1 reference: `/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/FINAL-STATUS-AND-BENCHMARKS.md`
