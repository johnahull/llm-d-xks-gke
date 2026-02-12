# Service Backend HTTPS Protocol Mismatch

## Status: Known Limitation (Accepted)

This is an inherent incompatibility between KServe's Istio-oriented design and GKE's native Gateway API. The limitation affects only non-inference endpoints and does not impact core functionality.

## Problem

KServe controller creates Services with `appProtocol: https`, causing GKE Gateway API to configure backend services for HTTPS. However, vLLM serves HTTP only (not HTTPS), resulting in TLS errors on Service backend endpoints:

```
upstream connect error or disconnect/reset before headers.
transport failure reason: TLS_error:|268435703:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER
```

## Root Cause

**KServe was designed for Istio service mesh environments**, where:

1. Istio sidecar proxies handle TLS termination transparently
2. `appProtocol: https` tells Istio to encrypt service-to-service traffic via mTLS
3. The application (vLLM) never needs to implement HTTPS - Istio handles it

**Without Istio (GKE native Gateway):**

1. GKE reads `appProtocol: https` from the Service spec
2. GKE configures the GCP backend service for HTTPS
3. GKE connects directly to vLLM over HTTPS
4. vLLM only speaks HTTP - TLS handshake fails

**Why this can't be fixed without Istio:**

| Approach | Why It Fails |
|----------|-------------|
| Patch Service `appProtocol` to `http` | KServe controller reconciles it back to `https` immediately |
| `cloud.google.com/app-protocols` annotation | Only works for GKE Ingress, not Gateway API |
| Kyverno admission controller | KServe controller reconciles `appProtocol` back after mutation |
| GCPBackendPolicy CRD | No protocol override field available |
| Fork KServe controller | Unsustainable maintenance burden |
| Configure vLLM for HTTPS | vLLM doesn't support HTTPS natively; requires TLS sidecar |

## Impact

**Affected Endpoints (via Gateway):**
- `/health` - TLS error (routes through Service backend)
- `/v1/models` - TLS error (routes through Service backend)

**Working Endpoints (via Gateway):**
- `/v1/completions` - Works perfectly (routes through InferencePool backend)
- `/v1/chat/completions` - Works perfectly (routes through InferencePool backend)

**Why InferencePool endpoints work:**
InferencePool backends use headless services without `appProtocol`, so GKE defaults to HTTP. Only the ClusterIP Service (for non-inference endpoints) has the HTTPS issue.

## Why This Is Acceptable

1. **Core functionality is unaffected** - All inference endpoints (`/v1/completions`, `/v1/chat/completions`) work perfectly
2. **Health/models accessible directly** - These endpoints can be reached via direct pod access or `kubectl port-forward` for debugging
3. **GCP health checks work independently** - HealthCheckPolicy CRDs configure GCP health checks directly, bypassing the Gateway protocol issue
4. **Production inference is the primary use case** - `/health` and `/v1/models` are debugging/monitoring endpoints, not client-facing

## Workarounds for Non-Inference Endpoints

### Direct Pod Access
```bash
# Get pod IP
POD_IP=$(kubectl get pod -n llm-d-inference-scheduling \
  -l app.kubernetes.io/component=workload \
  -o jsonpath='{.items[0].status.podIP}')

# Health check
kubectl run -it --rm --image=curlimages/curl test -- curl http://$POD_IP:8000/health

# List models
kubectl run -it --rm --image=curlimages/curl test -- curl http://$POD_IP:8000/v1/models
```

### Port Forwarding
```bash
kubectl port-forward -n llm-d-inference-scheduling svc/qwen2-3b-pattern1-kserve-workload-svc 8000:8000

# In another terminal:
curl http://localhost:8000/health
curl http://localhost:8000/v1/models
```

## Permanent Fix Options

If routing `/health` and `/v1/models` through the Gateway becomes a requirement:

1. **Deploy Istio** - KServe's intended environment; all endpoints work transparently
2. **Add TLS sidecar to vLLM pods** - nginx/envoy sidecar terminates TLS before forwarding to vLLM on localhost
3. **Upstream fix in KServe** - Contribute a configurable `appProtocol` option to the KServe controller

## Technical Details

### GCP Backend Services

Pattern 1 creates two backend services:

1. **InferencePool Backend** (HTTP - works)
   - Routes: `/v1/completions`, `/v1/chat/completions`
   - Backend: InferencePool (headless service, no `appProtocol` set)
   - Protocol: HTTP (GKE default)

2. **Service Backend** (HTTPS - broken)
   - Routes: `/health`, `/v1/models`, catch-all (`/`)
   - Backend: ClusterIP Service with `appProtocol: https`
   - Protocol: HTTPS (set by GKE based on `appProtocol`)

### GKE Protocol Determination (Gateway API)

For Gateway API backends, GKE determines protocol from:
1. Service port's `appProtocol` field (primary)
2. Port name as fallback (e.g., "https" implies HTTPS)

The `cloud.google.com/app-protocols` annotation is **only** used for GKE Ingress, not Gateway API.

---

**Status:** Known Limitation (Accepted)
**Date:** 2026-02-12
**Impact:** Non-inference endpoints only; core inference functionality unaffected
**Resolution:** Accept limitation; use direct pod access for `/health` and `/v1/models` if needed
