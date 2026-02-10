# Pattern 1 Manifests

This directory contains Kubernetes manifests for deploying Pattern 1 (single replica baseline).

## Files

### `httproute-pattern1.yaml`
HTTPRoute that routes all traffic to the Pattern 1 InferencePool.

- Routes all requests with path prefix `/` to the `gaie-pattern1` InferencePool
- Single backend with 100% weight
- Simple baseline routing with no intelligent load balancing

## Deployment

After deploying the model with helmfile, apply this manifest:

```bash
kubectl apply -f patterns/pattern1-baseline/manifests/httproute-pattern1.yaml -n llm-d-inference-scheduling
```

Verify the HTTPRoute:

```bash
kubectl get httproute -n llm-d-inference-scheduling
```

## See Also

- [Pattern 1 GPU Setup Guide](../llm-d-pattern1-gpu-setup.md)
- [Pattern 1 TPU Setup Guide](../llm-d-pattern1-tpu-setup.md)
