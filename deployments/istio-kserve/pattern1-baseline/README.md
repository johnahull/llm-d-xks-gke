# Pattern 1: Baseline Single Replica (Istio/KServe)

Single replica deployment using **Istio service mesh** and **KServe LLMInferenceService** for declarative vLLM management.

## Technology Stack

- **Service Mesh**: Red Hat OpenShift Service Mesh (OSSM 3.1.x) via sail-operator
- **Serving**: KServe v0.15 LLMInferenceService CRD
- **Gateway**: Istio Ingress Gateway with Gateway API
- **Routing**: InferencePool v1alpha2 with EPP scheduler
- **Security**: NetworkPolicy isolation, TLS termination at gateway

## Quick Start

See [cluster-deployment-guide.md](docs/cluster-deployment-guide.md) for complete deployment steps.

## Key Files

- **[istio-kserve-architecture.md](docs/istio-kserve-architecture.md)** - Architecture overview
- **[llmisvc-tpu.yaml](manifests/llmisvc-tpu.yaml)** - KServe deployment manifest
- **[security-model.md](docs/security-model.md)** - Security hardening guide
- **[cluster-architecture.md](docs/cluster-architecture.md)** - Network architecture documentation
- **[cluster-deployment-guide.md](docs/cluster-deployment-guide.md)** - Step-by-step deployment guide

## Deployment

This pattern uses KServe's **LLMInferenceService** CRD, which provides:
- Declarative vLLM deployment configuration
- Automatic HTTPRoute and InferencePool creation by KServe controller
- Integration with Istio service mesh for traffic management
- NetworkPolicy-based security hardening

```bash
# Deploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml

# Apply NetworkPolicies
kubectl apply -f manifests/networkpolicies/
```

## API Access

**Deployed Model:** Qwen2.5-3B-Instruct on TPU v6e-4

**Base URL:** `http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1`

See [API-ACCESS.md](API-ACCESS.md) for complete API usage examples and OpenAI client integration.

### Quick Test

```bash
# List models
curl http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models

# Chat completion
curl -X POST http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}'
```

## Testing & Benchmarks

- [scripts/test-cluster.sh](scripts/test-cluster.sh) - Cluster validation
- [scripts/benchmark-cluster.sh](scripts/benchmark-cluster.sh) - Performance benchmarking

**Latest Benchmark Results** (2026-02-10):
- Peak throughput: 14.32 req/sec (concurrency 20)
- Average latency: ~1400ms
- Reliability: 0 failures across 180 requests

See [benchmarks/results/cluster/](benchmarks/results/cluster/) for detailed results.

## Documentation

- [Istio/KServe Architecture](docs/istio-kserve-architecture.md) - Complete integration guide
- [Deployment Session Notes](docs/deployment-session-2026-02-06.md) - Actual deployment log
- [Kustomize Fix](docs/kustomize-fix.md) - KServe odh-xks overlay fix
- [Issues and Troubleshooting](docs/issues-istio.md) - Known issues and solutions
