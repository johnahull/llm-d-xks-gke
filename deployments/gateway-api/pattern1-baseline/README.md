# Pattern 1: Baseline Single Replica (Gateway API/llm-d)

Single replica deployment using **llm-d Helm charts** with Gateway API for intelligent routing.

## Technology Stack

- **Framework**: llm-d (Kubernetes-native distributed LLM inference)
- **Deployment**: Helm + helmfile
- **Gateway**: GKE Gateway API
- **Routing**: InferencePool with EPP scheduler
- **Serving**: Direct vLLM deployment via Helm

## Quick Start

**GPU Deployment**: See [llm-d-gpu-setup.md](docs/llm-d-gpu-setup.md)
**TPU Deployment**: See [llm-d-tpu-setup.md](docs/llm-d-tpu-setup.md)

## Key Files

- **[llm-d-pattern1-values.yaml](llm-d-pattern1-values.yaml)** - Helm values for llm-d modelservice
- **[manifests/httproute.yaml](manifests/httproute.yaml)** - Manual HTTPRoute for routing
- **[manifests/README.md](manifests/README.md)** - Helm deployment instructions

## Deployment

This pattern uses llm-d's **Helm-based deployment** with manual HTTPRoute creation:

```bash
# Deploy via helmfile (from repository root)
cd /home/jhull/devel/llm-d
helmfile -f helmfile.yaml.gotmpl apply

# Apply HTTPRoute manually
kubectl apply -f manifests/httproute.yaml
```

See the setup guides for complete deployment procedures with GPU or TPU accelerators.

## Differences from Istio/KServe

**llm-d Approach:**
- Helm-based deployment with explicit values files
- Manual HTTPRoute manifest creation
- Direct vLLM pod management via Helm
- No service mesh required (GKE Gateway API only)

**Istio/KServe Approach:**
- Declarative LLMInferenceService CRD
- Automatic HTTPRoute creation by KServe controller
- KServe manages vLLM lifecycle
- Requires Istio service mesh integration

## Benchmarks

See [benchmarks/](benchmarks/) for performance testing results.
