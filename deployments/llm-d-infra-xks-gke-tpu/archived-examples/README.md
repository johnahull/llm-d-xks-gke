# Archived Examples

This directory contains configuration files that are **NOT used** in the main deployment but are kept for reference purposes.

## llm-d-helm-alternative.yaml

**Status:** ARCHIVED - Not used for KServe deployment

**Original Purpose:** This file was initially created as a Helm values file for deploying workloads using the llm-d modelservice Helm chart.

**Why Archived:**
This deployment uses **KServe LLMInferenceService CRD** (declarative manifest) instead of llm-d Helm charts for workload deployment.

**Current Approach:**
- **Infrastructure**: llm-d-infra-xks operators (deployed via Makefile)
- **Workload**: KServe LLMInferenceService manifest (see `../manifests/llmisvc-tpu.yaml`)
- **Deployment Method**: `kubectl apply -f manifests/llmisvc-tpu.yaml`

**Key Architectural Difference:**

| Approach | Configuration | Deployment Command | Resource Management |
|----------|--------------|-------------------|-------------------|
| **llm-d Helm** (archived) | Helm values.yaml | `helm install ...` | Manual HTTPRoute/InferencePool creation |
| **KServe CRD** (current) | LLMInferenceService YAML | `kubectl apply -f ...` | Automatic HTTPRoute/InferencePool creation |

**Benefits of KServe Approach:**
1. **Automatic resource creation** - KServe controller auto-creates HTTPRoute and InferencePool
2. **Declarative management** - Single manifest describes entire deployment
3. **Better integration** - KServe controller manages full lifecycle
4. **Proven patterns** - Based on working istio-kserve/pattern1-baseline deployment

**If You Want to Use llm-d Helm Instead:**

For reference, llm-d Helm deployment is used in:
- `deployments/gateway-api/pattern1-baseline/` - Production example with llm-d Helm
- See [llm-d documentation](https://llm-d.ai/docs/usage/getting-started-inferencing) for Helm chart details

**This file is kept for:**
- Historical reference
- Comparison between deployment approaches
- Alternative implementation exploration

**Do not use this file** for the main deployment. It will not work with the KServe-based architecture.

---

Last Updated: 2026-02-11
