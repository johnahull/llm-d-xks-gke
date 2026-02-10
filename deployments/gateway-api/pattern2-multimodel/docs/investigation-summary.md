# Pattern 2 TPU Multi-Model Routing Investigation Summary

## Problem Statement
Pattern 2 TPU deployment has both models (Qwen2.5-3B and Phi-3-mini) deployed but routing accuracy is ~50% instead of the expected 100%.

## Root Cause Analysis

### Initial Diagnosis
- ❌ **INCORRECT**: Model labels (`llm-d.ai/model`) were thought to control routing
- ✅ **CORRECT**: EPP (Endpoint Picker Protocol) needs to extract model from request body

### Architecture Discovery

**What We Learned:**
1. **Body-Based Routing (BBR)** is **NOT** a separate service
   - It's built into the EPP image (`registry.k8s.io/gateway-api-inference-extension/epp`)
   - EPP already receives request body (`request_body_mode: FULL_DUPLEX_STREAMED`)
   - Missing: Configuration to **parse** and **route** based on model field

2. **Plugin System**:
   - Available plugins in v0.4.0: `queue-scorer`, `kv-cache-utilization-scorer`, `prefix-cache-scorer`
   - NOT available: `body_parser`, `model-filter`, `filter` with model-aware settings
   - The body-parsing logic exists in EPP but activation method unclear

3. **InferencePool Architecture**:
   - ✅ Created separate InferencePools (qwen-pool, phi-pool) with model-specific selectors
   - ✅ Each pool correctly selects its pod (verified via endpoints)
   - ❌ Both pools use same EPP service → EPP does round-robin across all backends

## What We Fixed

### Architecture Improvements
1. **Deleted Duplicate InferencePool**:
   - Removed `gaie-pattern2` release (was creating second scheduler)
   - Now have single scheduler managing both models

2. **Upgraded EPP**:
   - From: `ghcr.io/llm-d/llm-d-inference-scheduler:v0.4.0`
   - To: `ghcr.io/llm-d/llm-d-inference-scheduler:v0.4.0-rc.1`

3. **Created Model-Specific Infrastructure**:
   ```yaml
   # Separate InferencePools
   - qwen-pool → selects pods with label model-instance=qwen
   - phi-pool → selects pods with label model-instance=phi

   # Path-based HTTPRoutes
   - /qwen/* → qwen-pool
   - /phi/* → phi-pool
   ```

## Current Status

### Working Components
✅ Both vLLM pods running and serving correct models:
  - Pattern 1: `Qwen/Qwen2.5-3B-Instruct` (10.64.0.4:8000)
  - Pattern 2: `microsoft/Phi-3-mini-4k-instruct` (10.64.2.4:8000)

✅ Separate InferencePools correctly select their pods:
  - qwen-pool endpoints: 10.64.0.4:8000
  - phi-pool endpoints: 10.64.2.4:8000

✅ HTTPRoutes bound to Gateway:
  - /qwen/v1/completions → qwen-pool
  - /phi/v1/completions → phi-pool

### Not Working
❌ Routing accuracy still ~50%
❌ EPP does round-robin regardless of InferencePool

## Technical Gaps Identified

### Missing Configuration
The EPP ConfigMap needs configuration to:
1. Parse OpenAI-compatible JSON request body
2. Extract `model` field
3. Route based on that field

**Attempted Configurations (all failed "not found in registry"):**
```yaml
# Attempt 1: body_parser type
plugins:
- name: model-aware-router
  type: body_parser  # ❌ Not found

# Attempt 2: filter type with settings
plugins:
- name: model-aware-routing
  type: filter
  settings:
    header_name: x-model-id  # ❌ Unknown field "settings"
```

### Alternative Approaches Considered

**1. Body Based Router (BBR) as Separate Service**
- ❌ Image `ghcr.io/llm-d/llm-d-body-parser:v0.4.0` returns 403 Forbidden
- ✅ Confirmed: BBR logic is built into EPP, not a separate service

**2. RequestHeaderModifier in HTTPRoute**
- Tried injecting `x-model-id` header at Gateway level
- EPP doesn't have plugin to read this header

**3. Multiple InferencePools**
- ✅ Successfully created separate pools
- ❌ Both use same EPP → EPP balances across all backends

## Recommendations for Resolution

### Option 1: Enable Body-Based Routing in EPP (Preferred)
**Need**: Documentation or example showing correct EPP ConfigMap for body-based routing

Likely format (unconfirmed):
```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha1
kind: EndpointPickerConfig
featureGates:
  BodyBasedRouting: true  # Hypothetical
plugins:
  - type: queue-scorer
  - type: kv-cache-utilization-scorer
  - type: prefix-cache-scorer
```

### Option 2: Separate EPP per InferencePool
Create dedicated EPP deployments:
- qwen-epp → serves only qwen-pool
- phi-epp → serves only phi-pool

**Pros**: Clean separation, no body parsing needed
**Cons**: Higher resource usage, more complex

### Option 3: Use llm-d v0.5.x or RHAII GA
Wait for official release with documented body-based routing

## Files Modified

1. **EPP Configuration**:
   - ConfigMap: `gaie-pattern1-epp` (multiple attempted configurations)
   - Deployment: Upgraded image to v0.4.0-rc.1

2. **InferencePools**:
   - Created: `qwen-pool`, `phi-pool`
   - Deleted: `gaie-pattern2` (duplicate)

3. **HTTPRoutes**:
   - Created: `qwen-route` (/qwen/*), `phi-route` (/phi/*)
   - Deleted: `llm-d-multi-model-inference` (conflicting unified route)

4. **Pod Labels**:
   - Added: `model-instance=qwen` to Pattern 1 pod
   - Added: `model-instance=phi` to Pattern 2 pod

5. **Override Files** (updated but not deployed):
   - `pattern1-tpu-overrides.yaml`: Changed label to "Qwen/Qwen2.5-3B-Instruct"
   - `pattern2-tpu-overrides.yaml`: Changed label to "microsoft/Phi-3-mini-4k-instruct"
   - Note: Labels don't affect routing; kept for documentation

## Test Results

### Current Routing Accuracy
```
Qwen via /qwen/v1/completions: 5/10 (50%)
Phi-3 via /phi/v1/completions: 3/10 (30%)
```

### Expected with Body-Based Routing
```
Qwen: 10/10 (100%)
Phi-3: 10/10 (100%)
```

## Questions for llm-d Team

1. **What is the correct plugin type/configuration for body-based routing in EPP v0.4.0?**
   - Is there a feature gate to enable?
   - Is there example ConfigMap we can reference?

2. **Does body-based routing require a specific EPP image version?**
   - We're using `ghcr.io/llm-d/llm-d-inference-scheduler:v0.4.0-rc.1`
   - Should we use `registry.k8s.io/gateway-api-inference-extension/epp:v1.2.0`?

3. **Is the multiple-InferencePool approach correct?**
   - Should each pool have its own EPP?
   - Or should single EPP be able to route based on request body?

## Deployment Architecture (Current)

```
Internet → Gateway (35.214.154.17)
             ↓
        ┌────────────────────┐
        │ HTTPRoute          │
        │ /qwen/* → qwen-pool│
        │ /phi/*  → phi-pool │
        └────────────────────┘
             ↓
        ┌────────────────────┐
        │ InferencePools     │
        │ - qwen-pool        │
        │ - phi-pool         │
        └────────────────────┘
             ↓
        Same EPP (gaie-pattern1-epp:9002)
             ↓
        Round-robin (50% each)
             ↓
        ┌──────────┬──────────┐
        │ Qwen Pod │ Phi Pod  │
        │ 10.64.0.4│ 10.64.2.4│
        └──────────┴──────────┘
```

## Next Steps

1. **Get llm-d documentation** for body-based routing configuration
2. **Test with `registry.k8s.io/gateway-api-inference-extension/epp:v1.2.0`** image
3. **Or** implement separate EPP per model as workaround
4. **Or** wait for RHAII GA with official multi-model routing support

## Key Learnings

1. **Model labels don't control routing** - they're metadata only
2. **Body-based routing is in EPP**, not a separate service
3. **InferencePools route to EPP**, EPP routes to pods
4. **EPP needs configuration** to parse request body and extract model field
5. **v0.4.0-rc.1 ConfigMap format** is different from documentation examples
