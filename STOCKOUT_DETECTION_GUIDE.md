# GKE Accelerator Stockout Detection Guide

## The Stockout Problem

**Stockout** = Zone is listed as supporting an accelerator, but **zero capacity is actually available**.

### Common Scenarios

```bash
# What the API says:
./check-gke-accelerator-availability.sh us-west4-a
✅ NVIDIA H100 GPU is SUPPORTED in us-west4-a

# What actually happens:
gcloud container node-pools create h100-pool \
  --machine-type=a3-highgpu-1g \
  --zone=us-west4-a
ERROR: ZONE_RESOURCE_POOL_EXHAUSTED: The zone does not have enough resources
```

### Why Stockouts Occur

1. **High Demand** - Popular accelerators (H100, A100) are in high demand
2. **Limited Supply** - Expensive hardware with manufacturing constraints
3. **Regional Concentration** - Most capacity in specific zones
4. **Quota vs Capacity** - You may have quota but zone has no physical hardware

## Detection Methods

### Method 1: Capacity Indicators (Default)

The prerequisites checker now includes capacity indicators:

```bash
./check-nodepool-prerequisites.sh \
  --zone us-central1-a \
  --machine-type n1-standard-4 \
  --accelerator nvidia-tesla-t4
```

**What it checks:**

```
Check 5b: Capacity Indicators
=========================================
✅ Found 7 instance(s) in us-central1-a
   Zone appears to have active compute capacity
✅ Found 7 GKE node(s) in us-central1-a
   This suggests GKE capacity is available
✅ Zone status: UP (operational)
```

**Indicators explained:**

| Indicator | Meaning | Reliability |
|-----------|---------|-------------|
| Existing instances in zone | Capacity was available recently | 🟢 High |
| Existing GKE nodes in zone | GKE has capacity | 🟢 High |
| Zone status: UP | Zone operational (not maintenance) | 🟢 High |
| No existing instances | May indicate stockout or new machine type | 🟡 Medium |

### Method 2: Actual Capacity Test (Experimental)

**⚠️ Warning:** This creates a real instance (immediately deleted) and may incur brief charges!

```bash
./check-nodepool-prerequisites.sh \
  --zone us-central1-a \
  --machine-type n1-standard-4 \
  --accelerator nvidia-tesla-t4 \
  --test-capacity
```

**What it does:**

1. Creates a small test instance in the zone
2. If successful → Capacity confirmed ✅
3. If failed → Analyzes error:
   - `QUOTA` error → Quota exhausted
   - `ZONE_RESOURCE_POOL_EXHAUSTED` → **STOCKOUT DETECTED**
   - Other errors → Configuration issue
4. Deletes test instance (if created)

**Output examples:**

**Success (capacity available):**
```
Check 7: Actual Capacity Test
=========================================
Testing GPU capacity by attempting instance creation...
   Instance name: capacity-test-1739298472
   This will take 10-20 seconds...

✅ CAPACITY AVAILABLE: Successfully created test GPU instance
   Deleting test instance...
✅ Test instance deleted
```

**Stockout detected:**
```
Check 7: Actual Capacity Test
=========================================
Testing GPU capacity by attempting instance creation...
   Instance name: capacity-test-1739298472
   This will take 10-20 seconds...

❌ STOCKOUT DETECTED: No capacity available in us-west4-a
   Try alternative zones or wait for capacity to become available
```

### Method 3: Manual Testing

If you want to test without using the script:

**GPU test:**
```bash
# Attempt creation
gcloud compute instances create stockout-test \
  --zone=us-west4-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-h100-80gb,count=1 \
  --boot-disk-size=10GB

# If successful, delete immediately
gcloud compute instances delete stockout-test --zone=us-west4-a --quiet
```

**TPU test:**
```bash
# Attempt creation
gcloud compute tpus tpu-vm create stockout-test \
  --zone=us-central1-b \
  --accelerator-type=v6e-1 \
  --version=tpu-vm-base

# If successful, delete immediately
gcloud compute tpus tpu-vm delete stockout-test --zone=us-central1-b --quiet
```

## Stockout Patterns by Accelerator Type

### High Stockout Risk 🔴

**NVIDIA H100** (newest, highest demand)
- Stockouts common in most zones
- Best availability: us-central1-a, us-east4-a
- Consider H100 reservations for guaranteed capacity

**NVIDIA A100** (premium tier, high demand)
- Moderate stockouts, especially A100-80GB
- Better availability in us-central1, us-east1
- A100-40GB generally more available than 80GB

### Medium Stockout Risk 🟡

**NVIDIA L4** (newer, growing demand)
- Occasional stockouts in popular zones
- Generally good availability
- us-central1 usually has capacity

**TPU v6e** (newest TPU, limited zones)
- Rare stockouts (only 9 zones total)
- High availability in supported zones
- us-central1-b typically reliable

### Low Stockout Risk 🟢

**NVIDIA T4** (mature, widely available)
- Stockouts very rare
- Available in 51+ zones (per API mode)
- us-central1-a highly reliable (used in production)

**TPU v5e** (mature, cost-effective)
- Stockouts uncommon
- 5 zones with stable capacity
- Good alternative to v6e

## Stockout Mitigation Strategies

### Strategy 1: Multi-Zone Deployment

Don't depend on a single zone:

```bash
# Check multiple zones
./check-nodepool-prerequisites.sh \
  --zone us-central1-a --machine-type a3-highgpu-1g
./check-nodepool-prerequisites.sh \
  --zone us-central1-b --machine-type a3-highgpu-1g
./check-nodepool-prerequisites.sh \
  --zone us-east4-a --machine-type a3-highgpu-1g
```

Pick the zone with best capacity indicators.

### Strategy 2: Autoscaling with Zero Minimum

Handle temporary stockouts gracefully:

```bash
gcloud container node-pools create gpu-pool \
  --machine-type=a3-highgpu-1g \
  --zone=us-central1-a \
  --enable-autoscaling \
  --min-nodes=0 \          # Can scale to zero during stockouts
  --max-nodes=10 \
  --num-nodes=1
```

**Benefits:**
- Node pool stays healthy during temporary stockouts
- Automatically scales up when capacity becomes available
- No manual intervention needed

### Strategy 3: Alternative Accelerators

Have fallback options:

```
Primary: H100 (best performance, high stockout risk)
   ↓
Fallback 1: A100 (80% performance, medium risk)
   ↓
Fallback 2: L4 (60% performance, low risk)
   ↓
Fallback 3: T4 (40% performance, very low risk)
```

### Strategy 4: Capacity Reservations

For critical workloads, reserve capacity:

```bash
# Create reservation (guarantees capacity for 1 year+)
gcloud compute reservations create h100-reservation \
  --zone=us-central1-a \
  --vm-count=10 \
  --machine-type=a3-highgpu-1g \
  --min-cpu-platform="Intel Sapphire Rapids"

# Use reservation in node pool
gcloud container node-pools create h100-pool \
  --reservation=h100-reservation \
  --machine-type=a3-highgpu-1g
```

**Pros:** Guaranteed capacity, no stockouts
**Cons:** 1-year commitment, upfront planning

### Strategy 5: Alternative Regions

Some regions have better availability:

**H100 Availability (best to worst):**
1. us-central1 (Iowa) - Best availability
2. us-east4 (Virginia) - Good availability
3. europe-west4 (Netherlands) - Moderate
4. asia-southeast1 (Singapore) - Limited

**Check availability across regions:**
```bash
./check-gke-accelerator-availability.sh --api --type gpu | grep -A50 "H100"
```

### Strategy 6: Off-Peak Deployment

Capacity often becomes available during off-peak hours:

- **Best times:** Weekends, late night Pacific Time
- **Worst times:** Monday mornings, end of quarter
- **Strategy:** Schedule cluster creation for off-peak windows

## Real-World Stockout Examples

### Example 1: H100 Stockout

```bash
$ ./check-nodepool-prerequisites.sh \
    --zone us-west4-a \
    --machine-type a3-highgpu-1g \
    --test-capacity

Check 5b: Capacity Indicators
=========================================
⚠️  No existing instances found in us-west4-a
   This may indicate limited capacity or new machine type
✅ Zone status: UP (operational)

Check 7: Actual Capacity Test
=========================================
❌ STOCKOUT DETECTED: No capacity available in us-west4-a
   Try alternative zones or wait for capacity to become available
```

**Resolution:** Try us-central1-a or us-east4-a instead.

### Example 2: Quota vs Stockout

```bash
# Quota exhausted
❌ QUOTA EXCEEDED: Insufficient quota
   → Solution: Request quota increase

# Stockout
❌ STOCKOUT DETECTED: No capacity available
   → Solution: Try different zone or wait
```

### Example 3: Successful Deployment

```bash
$ ./check-nodepool-prerequisites.sh \
    --zone us-central1-a \
    --machine-type n1-standard-4 \
    --accelerator nvidia-tesla-t4

Check 5b: Capacity Indicators
=========================================
✅ Found 7 instance(s) in us-central1-a
✅ Found 7 GKE node(s) in us-central1-a
✅ Zone status: UP (operational)

Summary
=========================================
✅ All checks PASSED!
```

**High confidence** - proceed with node pool creation.

## Workflow: Handling Stockouts

```
1. Check prerequisites (including capacity indicators)
   |
   v
2. All indicators green?
   |
   +-- YES → Proceed with node pool creation
   |
   +-- NO → Some indicators yellow/red
       |
       v
   3. Run --test-capacity for definitive answer
       |
       +-- PASS → Capacity available, proceed
       |
       +-- STOCKOUT → Try mitigation:
           |
           v
       4. Check alternative zones
           |
           v
       5. Consider alternative accelerators
           |
           v
       6. Set min-nodes=0 for autoscaling
           |
           v
       7. Wait for capacity (check periodically)
```

## Quick Reference

**Check capacity indicators (fast, free):**
```bash
./check-nodepool-prerequisites.sh \
  --zone <zone> \
  --machine-type <type> \
  --accelerator <gpu-type>
```

**Test actual capacity (slow, may incur brief charges):**
```bash
./check-nodepool-prerequisites.sh \
  --zone <zone> \
  --machine-type <type> \
  --accelerator <gpu-type> \
  --test-capacity
```

**Check multiple zones for best capacity:**
```bash
for zone in us-central1-{a,b,c,f}; do
  echo "Testing $zone..."
  ./check-nodepool-prerequisites.sh \
    --zone $zone \
    --machine-type a3-highgpu-1g
done
```

## Limitations

### What We Can Detect

✅ Zone operational status
✅ Existing successful deployments (good signal)
✅ Machine type availability
✅ Accelerator type support
✅ Actual capacity (with --test-capacity)

### What We Cannot Detect

❌ Future capacity availability
❌ Exact number of available GPUs/TPUs
❌ Capacity trends over time
❌ Planned maintenance windows
❌ Commitment/reservation usage by others

## Best Practices

1. **Always check capacity indicators before deployment**
2. **Use --test-capacity for critical deployments**
3. **Have multi-zone fallback plans**
4. **Enable autoscaling with min-nodes=0**
5. **Monitor stockout patterns for your accelerator**
6. **Consider reservations for production workloads**
7. **Deploy during off-peak hours when possible**
8. **Check alternative regions if primary is stocked out**

## Related Documentation

- [ACCELERATOR_CHECKER_GUIDE.md](./ACCELERATOR_CHECKER_GUIDE.md) - Zone availability checker
- [GKE_TPU_NODEPOOL_QUICKSTART.md](./GKE_TPU_NODEPOOL_QUICKSTART.md) - TPU deployment guide
- [Google Cloud TPU Availability](https://cloud.google.com/tpu/docs/regions-zones)
- [Google Cloud GPU Availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones)
