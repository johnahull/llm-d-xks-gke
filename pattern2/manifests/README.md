# Pattern 2 BBR Multi-Model Routing Manifests

This directory contains Kubernetes manifests for deploying Pattern 2 with Body-Based Router (BBR) model-aware routing.

## Overview

These manifests implement intelligent multi-model routing that achieved **100% routing accuracy** in benchmarks (see [PATTERN2_BBR_BENCHMARK_RESULTS.md](../PATTERN2_BBR_BENCHMARK_RESULTS.md)).

## Files

### `inferencepools-bbr.yaml`
Defines separate InferencePools for each model:
- **qwen-pool**: Routes to Qwen/Qwen2.5-3B-Instruct pods
- **phi-pool**: Routes to microsoft/Phi-3-mini-4k-instruct pods

Each pool uses the EPP (Endpoint Picker) service for intelligent endpoint selection.

### `httproutes-bbr.yaml`
Defines HTTPRoutes that match the `X-Gateway-Base-Model-Name` header injected by BBR:
- **qwen-model-route**: Matches header value `"Qwen/Qwen2.5-3B-Instruct"`
- **phi-model-route**: Matches header value `"microsoft/Phi-3-mini-4k-instruct"`

### `healthcheck-policy-fixed.yaml`
Defines GKE HealthCheckPolicies for each InferencePool:
- Uses `/health` endpoint (not `/`)
- Targets InferencePool resources (not Services)
- 15s interval and timeout

## Deployment

After deploying models with helmfile, apply these manifests:

```bash
# Apply InferencePools
kubectl apply -f pattern2/manifests/inferencepools-bbr.yaml -n llm-d-inference-scheduling

# Apply HTTPRoutes
kubectl apply -f pattern2/manifests/httproutes-bbr.yaml -n llm-d-inference-scheduling

# Apply HealthCheckPolicies
kubectl apply -f pattern2/manifests/healthcheck-policy-fixed.yaml -n llm-d-inference-scheduling
```

## Architecture

```
Client Request with model field
    ↓
BBR Filter (extracts model from request body)
    ↓
Sets header: X-Gateway-Base-Model-Name
    ↓
HTTPRoute (matches header value)
    ↓
InferencePool (routes to correct model pool)
    ↓
EPP (selects best endpoint)
    ↓
vLLM Pod
```

## See Also

- [Pattern 2 TPU Setup Guide](../llm-d-pattern2-tpu-setup.md)
- [Pattern 2 GPU Setup Guide](../llm-d-pattern2-gpu-setup.md)
- [BBR Benchmark Results](../PATTERN2_BBR_BENCHMARK_RESULTS.md)
