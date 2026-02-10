# Documentation Index

Centralized documentation for llmd-gke deployment patterns and guides.

## Quick Navigation

### Deployment Guides
Production-grade deployment methodologies for Kubernetes-based LLM inference.

- [GKE Inference Gateway + Istio](./deployment-guides/gke-inference-gateway-istio.md) - GKE-native deployment with Gateway API
- [Cloud-Agnostic LLM Deployment](./deployment-guides/cloud-agnostic-llm.md) - Portable deployment for any Kubernetes
- [Verification Guide](./deployment-guides/verification.md) - Post-deployment validation

### Benchmarking
Performance testing and optimization guides.

- [Benchmarking Methodology](./benchmarking.md) - Comprehensive benchmarking guide
- [Quickstart Guide](./benchmarking-quickstart.md) - Fast track to running benchmarks
- [Multi-Model Updates](./multi-model-updates.md) - Multi-model routing performance

## Pattern Documentation

Pattern-specific documentation organized by technology stack:

### Istio/KServe Deployments
- [Pattern 1: Baseline](../deployments/istio-kserve/pattern1-baseline/README.md) - Istio + KServe single replica

### Gateway API/llm-d Deployments
- [Pattern 1: Baseline](../deployments/gateway-api/pattern1-baseline/README.md) - llm-d Helm single replica
- [Pattern 2: Multi-Model](../deployments/gateway-api/pattern2-multimodel/README.md) - Multi-model routing
- [Pattern 3: Caching](../deployments/gateway-api/pattern3-caching/README.md) - N/S-caching scale-out (3 replicas)
- [Pattern 4: MoE](../deployments/gateway-api/pattern4-moe/README.md) - Mixture of Experts

## External Dependencies

External repositories (llm-d, llm-d-infra-xks) should be cloned as siblings:

```bash
cd /home/jhull/devel
git clone https://github.com/llm-d/llm-d.git
git clone https://github.com/llm-d-incubation/llm-d-infra.git llm-d-infra-xks
```

See [helm-configs/README.md](../helm-configs/README.md) for setup instructions.
