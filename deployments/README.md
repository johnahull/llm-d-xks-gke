# Deployment Patterns by Technology Stack

This directory contains deployment configurations organized by **technology stack**, providing clear separation between different approaches to running LLM inference on Kubernetes.

## Technology Stack Overview

### Istio/KServe Stack
**Directory**: `istio-kserve/`

Declarative, controller-driven deployment using KServe and Istio service mesh.

**Key Characteristics:**
- **Deployment Method**: KServe `LLMInferenceService` CRD
- **Service Mesh**: Red Hat OpenShift Service Mesh (OSSM 3.1.x) via sail-operator
- **Gateway**: Istio Ingress Gateway with Gateway API
- **Automation**: KServe controller automatically creates HTTPRoute and InferencePool
- **Security**: NetworkPolicy isolation, TLS termination at gateway
- **Best For**: Production environments requiring service mesh capabilities, declarative infrastructure

**Available Patterns:**
- [Pattern 1: Baseline](./istio-kserve/pattern1-baseline/README.md) - Single replica deployment

### Gateway API/llm-d Stack
**Directory**: `gateway-api/`

Helm-based deployment with llm-d framework for intelligent routing.

**Key Characteristics:**
- **Deployment Method**: Helm + helmfile
- **Framework**: llm-d (Kubernetes-native distributed LLM inference)
- **Gateway**: GKE Gateway API (no Istio required)
- **Routing**: Manual HTTPRoute and InferencePool creation
- **Serving**: Direct vLLM pod management via Helm charts
- **Best For**: Multi-pattern exploration, explicit configuration control, lighter infrastructure

**Available Patterns:**
- [Pattern 1: Baseline](./gateway-api/pattern1-baseline/README.md) - Single replica deployment
- [Pattern 2: Multi-Model](./gateway-api/pattern2-multimodel/README.md) - Multiple models with intelligent routing
- [Pattern 3: N/S-Caching](./gateway-api/pattern3-caching/README.md) - Scale-out with prefix caching (3 replicas)
- [Pattern 4: MoE](./gateway-api/pattern4-moe/README.md) - Mixture of Experts multi-node deployment

## Comparison Matrix

| Feature | Istio/KServe | Gateway API/llm-d |
|---------|--------------|-------------------|
| **Deployment Style** | Declarative CRD | Imperative Helm |
| **HTTPRoute Creation** | Automatic (KServe controller) | Manual manifest |
| **InferencePool Creation** | Automatic (KServe controller) | Manual manifest |
| **Service Mesh** | Required (Istio) | Optional (none used) |
| **vLLM Management** | KServe controller | Direct Helm charts |
| **Configuration Complexity** | Lower (automation) | Higher (explicit) |
| **Infrastructure Weight** | Heavier (Istio + KServe) | Lighter (Gateway API only) |
| **TLS/Security** | Built-in NetworkPolicies | Manual configuration |
| **Multi-Model Support** | Limited (Pattern 1 only) | Full (Patterns 2-4) |
| **Production Readiness** | High (enterprise service mesh) | Medium (requires manual config) |

## Choosing a Technology Stack

### Choose Istio/KServe if you:
- Need enterprise-grade service mesh capabilities
- Prefer declarative infrastructure (GitOps-friendly)
- Want automatic HTTPRoute/InferencePool creation
- Require built-in NetworkPolicy security hardening
- Are deploying in Red Hat OpenShift environments
- Value controller automation over explicit configuration

### Choose Gateway API/llm-d if you:
- Want to explore multiple deployment patterns (multi-model, caching, MoE)
- Prefer explicit, visible configuration over automation
- Need lighter infrastructure (no service mesh)
- Want direct control over Helm values and vLLM parameters
- Are prototyping or experimenting with different architectures
- Value flexibility over automation

## Common Elements

Both stacks share:
- **Gateway API** for routing (HTTPRoute, InferencePool)
- **vLLM** as the inference runtime
- **RHAIIS** (Red Hat AI Inference Services) container images
- **TPU and GPU support** (Google Cloud TPU v6e, NVIDIA T4)
- **OpenAI-compatible API** endpoints
- **Prometheus metrics** for observability

## Getting Started

### Istio/KServe Quick Start
```bash
# See complete guide
cd deployments/istio-kserve/pattern1-baseline
cat docs/cluster-deployment-guide.md

# Key deployment command
kubectl apply -f manifests/llmisvc-tpu.yaml
```

### Gateway API/llm-d Quick Start
```bash
# See complete guides
cd deployments/gateway-api/pattern1-baseline
cat docs/llm-d-tpu-setup.md  # For TPU
cat docs/llm-d-gpu-setup.md  # For GPU

# Key deployment command (from llm-d repo)
cd /home/jhull/devel/llm-d
helmfile -f helmfile.yaml.gotmpl apply
```

## Documentation

### Centralized Documentation
- [docs/](../docs/README.md) - Shared benchmarking and deployment guides
- [helm-configs/](../helm-configs/README.md) - llm-d Helm configuration
- [benchmarks/](../benchmarks/README.md) - Shared benchmarking infrastructure

### Tech Stack Documentation
- [Istio/KServe Architecture](./istio-kserve/pattern1-baseline/docs/istio-kserve-architecture.md)
- [Gateway API/llm-d Setup Guides](./gateway-api/pattern1-baseline/docs/)

## External Dependencies

Both stacks require cloning llm-d repositories as siblings:

```bash
cd /home/jhull/devel
git clone https://github.com/llm-d/llm-d.git
git clone https://github.com/llm-d-incubation/llm-d-infra.git llm-d-infra-xks
```

## Migration Between Stacks

To switch from one tech stack to another:

1. **Istio/KServe → Gateway API/llm-d**:
   - Delete KServe LLMInferenceService: `kubectl delete llmis <name>`
   - KServe controller will auto-cleanup HTTPRoute and InferencePool
   - Deploy via Helm: `helmfile apply`
   - Manually create HTTPRoute: `kubectl apply -f manifests/httproute.yaml`

2. **Gateway API/llm-d → Istio/KServe**:
   - Delete Helm deployment: `helmfile destroy`
   - Delete manual HTTPRoute: `kubectl delete httproute <name>`
   - Deploy KServe: `kubectl apply -f manifests/llmisvc-tpu.yaml`
   - KServe controller auto-creates HTTPRoute and InferencePool

## Pattern Evolution

Pattern availability by tech stack:

| Pattern | Istio/KServe | Gateway API/llm-d |
|---------|--------------|-------------------|
| 1: Baseline | ✅ Available | ✅ Available |
| 2: Multi-Model | ❌ Not yet | ✅ Available |
| 3: N/S-Caching | ❌ Not yet | ✅ Available |
| 4: MoE | ❌ Not yet | ✅ Available |

Future work may expand Istio/KServe to support additional patterns.
