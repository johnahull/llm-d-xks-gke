# BBR (Body Based Router) Implementation Attempt for Pattern 2 GPU

---
## ⚠️ UPDATE 2026-01-27: BBR NOW WORKS ✅

**The BBR approach described below was INCORRECT.** The real issue was missing **model allowlist ConfigMaps**, not EPP configuration.

**✅ BBR is now successfully deployed and working with 100% routing accuracy.**

**See:** `pattern2/BBR_SUCCESS.md` for the working implementation.

**Key Missing Component:** ConfigMaps with label `inference.networking.k8s.io/bbr-managed: "true"` that define baseModel mappings. Without these, BBR cannot populate the `X-Gateway-Base-Model-Name` header value, causing all requests to fail with 404 "fault filter abort".

---

## Summary (OUTDATED - See BBR_SUCCESS.md)

**Attempted:** Implementing BBR architecture with separate InferencePools per model to eliminate retry requirement.

**Result:** **FAILED** - BBR approach is not viable without deploying separate EPP (Endpoint Picker) instances per InferencePool.

**CORRECTION:** This conclusion was WRONG. The actual issue was missing allowlist ConfigMaps, not EPP configuration. BBR works perfectly with shared EPP when allowlist ConfigMaps are present.

**Current Status:** ~~Reverted to unified InferencePool approach with client-side retry logic (documented in `EPP_BACKEND_DISCOVERY_LIMITATION.md`)~~ **BBR is now working (see `pattern2/BBR_SUCCESS.md`)**.

---

## What We Tried

### BBR Architecture

The BBR (Body Based Router) approach used successfully in Pattern 2 TPU:

```yaml
# Separate InferencePool per model
InferencePool: gaie-pattern2-phi3
  selector: {llm-d.ai/model-name: phi-3-mini}  # Only 1 backend pod
  endpointPickerRef: gaie-pattern2-epp

InferencePool: gaie-pattern2-gemma
  selector: {llm-d.ai/model-name: gemma-2b}   # Only 1 backend pod
  endpointPickerRef: gaie-pattern2-epp

# Header-based HTTPRoutes
HTTPRoute: llm-d-pattern2-phi3-route
  matches:
    - headers: [{name: x-model-name, value: microsoft/Phi-3-mini-4k-instruct}]
  backendRefs: [InferencePool: gaie-pattern2-phi3]

HTTPRoute: llm-d-pattern2-gemma-route
  matches:
    - headers: [{name: x-model-name, value: google/gemma-2b-it}]
  backendRefs: [InferencePool: gaie-pattern2-gemma]
```

### Theory

With single-backend InferencePools (each pool selects only ONE pod via strict label selectors):
- No multi-model discovery issue (EPP only sees one backend per pool)
- Header-based routing ensures correct pool selection
- Should achieve 100% routing accuracy without retry logic

---

## Why It Failed

### Root Cause: EPP Configuration

The EPP (Endpoint Picker) deployment is configured with:

```yaml
args:
  - --pool-name
  - gaie-pattern2        # ← HARDCODED to monitor only this pool
  - --pool-namespace
  - llm-d
```

**Implication:**
- EPP monitors **ONLY** the `gaie-pattern2` InferencePool
- New pools (`gaie-pattern2-phi3`, `gaie-pattern2-gemma`) reference the same EPP service
- But EPP does NOT discover backends for these new pools (not in its monitoring scope)
- Result: InferencePools have no functional endpoint picker

### Observable Behavior

**Test Results:**
```bash
# Testing with BBR configuration applied
$ curl -X POST http://35.209.92.117/v1/completions \
  -H "x-model-name: microsoft/Phi-3-mini-4k-instruct" \
  -d '{"model": "microsoft/Phi-3-mini-4k-instruct", "prompt": "Hello", "max_tokens": 5}'

# Result: "no healthy upstream" (100% failure rate)
```

**EPP Logs:**
```json
{"level":"error","msg":"Error unmarshalling request body","body":"no healthy upstream"}
```

**InferencePool Status:**
- Status: Accepted ✓
- Parent Gateway: Resolved ✓
- Backend Endpoints: **NONE** (EPP not discovering backends)

### Why Pattern 2 TPU BBR Works

Pattern 2 TPU deployment uses **separate EPP instances per InferencePool**:

```yaml
# Pattern 2 TPU (WORKING)
InferencePool: gaie-pattern2-qwen
  endpointPickerRef: gaie-pattern2-qwen-epp   # Dedicated EPP

InferencePool: gaie-pattern2-phi3
  endpointPickerRef: gaie-pattern2-phi3-epp   # Dedicated EPP

# Each EPP configured for its specific pool:
Deployment: gaie-pattern2-qwen-epp
  args: ["--pool-name", "gaie-pattern2-qwen"]

Deployment: gaie-pattern2-phi3-epp
  args: ["--pool-name", "gaie-pattern2-phi3"]
```

**Pattern 2 GPU does NOT have separate EPP deployments**, hence the BBR approach fails.

---

## Solution Requirements

### Option 1: Deploy Separate EPP Instances (Not Implemented)

**Required Changes:**

1. **Deploy `gaie-pattern2-phi3-epp`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gaie-pattern2-phi3-epp
  namespace: llm-d
spec:
  template:
    spec:
      containers:
      - name: epp
        image: ghcr.io/llm-d/llm-d-inference-scheduler:v0.4.0
        args:
          - --pool-name
          - gaie-pattern2-phi3  # ← Monitor phi3 pool
          - --pool-namespace
          - llm-d
---
apiVersion: v1
kind: Service
metadata:
  name: gaie-pattern2-phi3-epp
  namespace: llm-d
spec:
  selector:
    app: gaie-pattern2-phi3-epp
  ports:
  - port: 9002
```

2. **Deploy `gaie-pattern2-gemma-epp`** (similar configuration)

3. **Update InferencePools to reference dedicated EPPs:**
```yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: gaie-pattern2-phi3
spec:
  endpointPickerRef:
    name: gaie-pattern2-phi3-epp  # ← Use dedicated EPP
```

**Pros:**
- Achieves 100% routing accuracy without retry logic
- Each EPP monitors its specific pool

**Cons:**
- Complex deployment (3 EPP instances total: unified + phi3 + gemma)
- Increased resource usage
- Maintenance overhead

### Option 2: BBR Filter (Not Available)

Use GKE Gateway BBR filter to inject `x-model-name` header from request body automatically.

**Status:** GKE Gateway API does not currently support BBR filter deployment or configuration.

---

## Current Working Solution

### Unified InferencePool with Client-Side Retry Logic

**Configuration:**
```yaml
InferencePool: gaie-pattern2
  selector: {llm-d.ai/inferenceServing: true}  # Matches ALL model pods
  endpointPickerRef: gaie-pattern2-epp

HTTPRoute: llm-d-pattern2-inference-scheduling
  matches: [{path: {type: PathPrefix, value: /v1/}}]
  backendRefs: [InferencePool: gaie-pattern2]
```

**Behavior:**
- EPP discovery limitation: queries one backend at a time (DNS round-robin)
- Success rate without retry: **40-60%**
- Success rate with retry logic: **100%** (avg 2.0-2.2 attempts)

**Retry Logic:** See `benchmarks/python/pattern2_benchmark_retry.py`

---

## Test Results

### BBR Configuration Testing

| Configuration | Success Rate | Error |
|---------------|--------------|-------|
| **BBR with shared EPP** | 0% | "no healthy upstream" |
| **Unified with retry** | 100% | None (2-2.2 retry avg) |
| **Unified without retry** | 50% | "model not found" (intermittent) |

### Pod Labels Verification

```bash
$ kubectl get pods -n llm-d -l llm-d.ai/inferenceServing=true \
  -o custom-columns=NAME:.metadata.name,MODEL-LABEL:.metadata.labels.llm-d\\.ai/model-name,READY:.status.conditions[?\(@.type==\"Ready\"\)].status

NAME                                                     MODEL-LABEL   READY
ms-pattern1-llm-d-modelservice-decode-5d8b4974b5-99zbh   gemma-2b      True
ms-pattern2-llm-d-modelservice-decode-6dc8fdb9bf-ks6lt   phi-3-mini    True
```

Labels correctly applied but BBR approach still failed due to EPP limitation.

---

## Conclusion

**BBR is NOT viable for Pattern 2 GPU without deploying separate EPP instances per model.**

The current unified InferencePool approach with client-side retry logic is the practical solution:
- Achieves 100% success rate
- Simple infrastructure (single EPP, single InferencePool)
- Retry overhead is minimal (2-2.2 attempts average)
- Well-documented in `benchmarks/EPP_BACKEND_DISCOVERY_LIMITATION.md`

**Recommendation:** Accept retry-based approach as the working solution for Pattern 2 GPU multi-model routing until:
1. Upstream EPP fix enables multi-backend aggregation, OR
2. Decision is made to deploy separate EPP instances (increased complexity)

---

## References

- **EPP Limitation Documentation**: `benchmarks/EPP_BACKEND_DISCOVERY_LIMITATION.md`
- **BBR Configuration (Non-Working)**: `patterns/pattern2-multimodel/manifests/pattern2-bbr-gpu.yaml`
- **Pattern 2 TPU (BBR Working)**: `patterns/pattern2-multimodel/docs/llm-d-tpu-setup.md`
- **Retry Logic Benchmark**: `benchmarks/python/pattern2_benchmark_retry.py`
- **Gateway IP**: 35.209.92.117
- **Current HTTPRoute**: `llm-d-pattern2-inference-scheduling` (unified)

---

## Files Modified During Attempt

1. **Added model-specific labels to deployments:**
   - `ms-pattern1-llm-d-modelservice-decode`: `llm-d.ai/model-name: gemma-2b`
   - `ms-pattern2-llm-d-modelservice-decode`: `llm-d.ai/model-name: phi-3-mini`
   - **Status:** Labels remain (useful metadata, no negative impact)

2. **Created BBR configuration file:**
   - `patterns/pattern2-multimodel/manifests/pattern2-bbr-gpu.yaml`
   - **Status:** Kept with warning header (documents why BBR doesn't work)

3. **BBR resources applied and reverted:**
   - InferencePools: `gaie-pattern2-phi3`, `gaie-pattern2-gemma` (deleted)
   - HTTPRoutes: `llm-d-pattern2-phi3-route`, `llm-d-pattern2-gemma-route` (deleted)
   - **Status:** Reverted to unified `llm-d-pattern2-inference-scheduling`

---

## Timestamp

- **Date:** 2026-01-27
- **BBR Applied:** 14:37:56 UTC
- **BBR Reverted:** 14:40:00 UTC (after confirming 0% success rate)
