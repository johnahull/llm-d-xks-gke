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

Pattern-specific documentation is located in the `patterns/` directory:

- [Pattern 1: Baseline](../patterns/pattern1-baseline/README.md) - Single replica deployment
- [Pattern 2: Multi-Model](../patterns/pattern2-multimodel/README.md) - Multi-model serving with intelligent routing
- [Pattern 3: Caching](../patterns/pattern3-caching/README.md) - N/S-caching scale-out (3 replicas)
- [Pattern 4: MoE](../patterns/pattern4-moe/README.md) - Mixture of Experts patterns

## External Dependencies

External repositories (llm-d, llm-d-infra-xks) should be cloned as siblings:

```bash
cd /home/jhull/devel
git clone https://github.com/llm-d/llm-d.git
git clone https://github.com/llm-d-incubation/llm-d-infra.git llm-d-infra-xks
```

See [helm-configs/README.md](../helm-configs/README.md) for setup instructions.
