# Machine Type Enhancement Proposal

## Current Gaps

### What's Missing
1. **Zone listings don't show machine types** - Users have to validate each zone individually to see machine type info
2. **No TPU topology guidance** - Users don't know what `--tpu-topology` values to use
3. **No example commands** - Users need to look up documentation for gcloud syntax
4. **GPU vs TPU creation differences not explained** - Different approaches are confusing

## What Users Need to Create Node Pools

### For GPUs (Current Model)
```bash
gcloud container node-pools create gpu-pool \
  --cluster=my-cluster \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \           # Base machine type
  --accelerator type=nvidia-tesla-t4,count=1 \  # Separate accelerator flag
  --num-nodes=1
```

**Key point:** GPUs use `--accelerator` flag separate from machine type

### For TPUs (Special Machine Types)
```bash
gcloud container node-pools create tpu-pool \
  --cluster=my-cluster \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-4t \        # Special TPU machine type (includes TPU!)
  --tpu-topology=2x2x1 \                   # TPU topology configuration
  --num-nodes=1
```

**Key point:** TPUs use special machine types (ct6e-*, ct5e-*, ct5p-*) that include the TPU

## TPU Machine Type Naming

**Format:** `ct{version}-standard-{chips}[t]`

### TPU v6e (Trillium)
- `ct6e-standard-1t` - 1 TPU chip (44 vCPUs, 176 GB RAM)
- `ct6e-standard-4t` - 4 TPU chips (180 vCPUs, 720 GB RAM)
- `ct6e-standard-8t` - 8 TPU chips (360 vCPUs, 1440 GB RAM)
- `ct6e-standard-16t` - 16 TPU chips
- `ct6e-standard-32t` - 32 TPU chips
- `ct6e-standard-64t` - 64 TPU chips
- `ct6e-standard-128t` - 128 TPU chips
- `ct6e-standard-256t` - 256 TPU chips

### TPU v5e
- `ct5e-standard-1` - 1 TPU chip (12 vCPUs, 48 GB RAM)
- `ct5e-standard-4` - 4 TPU chips (48 vCPUs, 192 GB RAM)
- `ct5e-standard-8` - 8 TPU chips (96 vCPUs, 384 GB RAM)
- `ct5e-standard-16` - 16 TPU chips
- `ct5e-standard-32` - 32 TPU chips
- etc.

### TPU v5p
- `ct5p-hightpu-1t` - 1 TPU chip (208 vCPUs, 832 GB RAM)
- `ct5p-hightpu-4t` - 4 TPU chips
- `ct5p-hightpu-8t` - 8 TPU chips
- etc.

## TPU Topology Values

The `--tpu-topology` flag defines the physical arrangement of TPU chips.

**Common topologies:**
- `1x1x1` - Single chip (default for 1-chip machine types)
- `2x2x1` - 4 chips in 2x2 grid (for 4-chip machine types)
- `2x2x2` - 8 chips in 2x2x2 cube (for 8-chip machine types)
- `2x2x4` - 16 chips
- `4x4x2` - 32 chips
- `4x4x4` - 64 chips
- `8x8x2` - 128 chips
- `8x8x4` - 256 chips

**Rule:** Topology must match machine type chip count:
- `ct6e-standard-4t` must use topology with 4 chips (2x2x1)
- `ct6e-standard-8t` must use topology with 8 chips (2x2x2, 4x2x1, etc.)

## Proposed Enhancements

### Option 1: Add --verbose Flag

**Default output (current):**
```
TPU v6e (Trillium) Supported Zones in GKE:
----------------------------------------
  us-central1-b        US Central
  us-east5-a           US East (Columbus)
```

**Verbose output (--verbose flag):**
```
TPU v6e (Trillium) Supported Zones in GKE:
----------------------------------------
Zone              Region              Machine Types
us-central1-b     US Central          ct6e-standard-{1t,4t,8t,16t,32t,64t,128t,256t}
us-east5-a        US East (Columbus)  ct6e-standard-{1t,4t,8t,16t,32t,64t,128t,256t}

NVIDIA T4 GPU Supported Zones in GKE:
----------------------------------------
Zone              Region              Machine Types
us-central1-a     US Central ⭐        n1-standard-* + --accelerator type=nvidia-tesla-t4
us-central1-b     US Central          n1-standard-* + --accelerator type=nvidia-tesla-t4
```

### Option 2: Add --examples Flag

Show practical gcloud commands for creating node pools:

```bash
./check-gke-accelerator-availability.sh --type tpu --examples
```

**Output:**
```
========================================
GKE TPU Node Pool Creation Examples
========================================

TPU v6e (Trillium) - Single Chip:
------------------------------------------
gcloud container node-pools create tpu-v6e-1chip \
  --cluster=my-cluster \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-1t \
  --num-nodes=1

TPU v6e (Trillium) - 4 Chips:
------------------------------------------
gcloud container node-pools create tpu-v6e-4chip \
  --cluster=my-cluster \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-4t \
  --tpu-topology=2x2x1 \
  --num-nodes=1

TPU v5e - 4 Chips:
------------------------------------------
gcloud container node-pools create tpu-v5e-4chip \
  --cluster=my-cluster \
  --zone=us-central1-a \
  --machine-type=ct5e-standard-4 \
  --tpu-topology=2x2x1 \
  --num-nodes=1
```

### Option 3: Add Machine Type Reference Section

Add to default output (after zone listings):

```
========================================
Machine Type Reference
========================================

GPU Node Pools:
  Use --machine-type + --accelerator flag:

  Example:
    --machine-type=n1-standard-4 \
    --accelerator type=nvidia-tesla-t4,count=1

  Common machine types:
    - n1-standard-{4,8,16,32} (T4 compatible)
    - a2-highgpu-{1g,2g,4g,8g} (A100 integrated)
    - g2-standard-{4,8,12,16,24,32,48,96} (L4 integrated)
    - a3-highgpu-{1g,2g,4g,8g} (H100 integrated)

TPU Node Pools:
  Use special machine type + --tpu-topology:

  TPU v6e: ct6e-standard-{1t,4t,8t,16t,32t,64t,128t,256t}
  TPU v5e: ct5e-standard-{1,4,8,16,32,64,128,256}
  TPU v5p: ct5p-hightpu-{1t,4t,8t,16t,32t,64t,128t,256t}

  Common topologies:
    1 chip:   (no --tpu-topology needed)
    4 chips:  --tpu-topology=2x2x1
    8 chips:  --tpu-topology=2x2x2
    16 chips: --tpu-topology=2x2x4
```

### Option 4: Enhanced Zone Validation

Current validation already shows machine types, but could add topology guidance:

**Current:**
```
✅ TPU v6e (Trillium) is SUPPORTED in us-central1-b
   Region: US Central
   Machine types: ct6e-standard-1t, ct6e-standard-4t, ct6e-standard-8t
```

**Enhanced:**
```
✅ TPU v6e (Trillium) is SUPPORTED in us-central1-b
   Region: US Central
   Machine types: ct6e-standard-{1t,4t,8t,16t,32t,64t,128t,256t}

   Example node pool creation:
   gcloud container node-pools create tpu-v6e-pool \
     --cluster=CLUSTER_NAME \
     --zone=us-central1-b \
     --machine-type=ct6e-standard-4t \
     --tpu-topology=2x2x1 \
     --num-nodes=1
```

## Recommended Implementation

**Minimal (Quick Win):**
- Add machine type reference section to default output
- Update zone validation to show example commands

**Comprehensive (Full Solution):**
- Add `--verbose` flag for detailed machine type listings
- Add `--examples` flag for gcloud command templates
- Add machine type reference section to default output
- Enhance zone validation with topology guidance

## User Questions Answered

### Q1: Should the script output machine types?
**A:** Yes, but the level of detail depends on use case:
- **Quick lookup:** Current zone listing is fine
- **Planning deployment:** Need machine type info (--verbose)
- **Learning:** Need examples and guidance (--examples)

### Q2: What is needed for gcloud to create TPU node pools?
**A:** Three key pieces:
1. **Zone** that supports the TPU version
2. **Machine type** (ct6e-standard-*, ct5e-standard-*, etc.)
3. **TPU topology** (--tpu-topology flag for multi-chip configs)

The script currently shows #1 (zones), but not #2 and #3.

## Implementation Priority

1. **High:** Add machine type reference section (helps all users)
2. **High:** Add --examples flag (learning/documentation use case)
3. **Medium:** Add --verbose flag (power user feature)
4. **Low:** Enhanced zone validation (nice-to-have, current validation is adequate)

## Questions for User

1. Which option(s) do you want implemented?
2. Should machine type info be shown by default, or behind a flag?
3. Do you want GPU machine type examples too, or just TPUs?
4. Should we add a --create-nodepool helper that generates the full command?
