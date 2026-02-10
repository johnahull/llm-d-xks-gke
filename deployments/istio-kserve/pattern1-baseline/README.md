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

## Testing

See [scripts/test-cluster.sh](scripts/test-cluster.sh) for cluster validation and [scripts/benchmark-cluster.sh](scripts/benchmark-cluster.sh) for performance benchmarking.

## Documentation

- [Istio/KServe Architecture](docs/istio-kserve-architecture.md) - Complete integration guide
- [Deployment Session Notes](docs/deployment-session-2026-02-06.md) - Actual deployment log
- [Kustomize Fix](docs/kustomize-fix.md) - KServe odh-xks overlay fix
- [Issues and Troubleshooting](docs/issues-istio.md) - Known issues and solutions
