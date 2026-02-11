# GKE TPU Node Pool Quick Reference

## TL;DR

**GPUs:** Use `--machine-type` + `--accelerator` flag
**TPUs:** Use special `ct*` machine types + `--tpu-topology` flag

## Creating TPU Node Pools

### TPU v6e (Trillium) - Recommended for Production

**Single chip (smallest/cheapest):**
```bash
gcloud container node-pools create tpu-v6e-1chip \
  --cluster=YOUR_CLUSTER \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-1t \
  --num-nodes=1
```

**4 chips (2x2 topology):**
```bash
gcloud container node-pools create tpu-v6e-4chip \
  --cluster=YOUR_CLUSTER \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-4t \
  --tpu-topology=2x2x1 \
  --num-nodes=1
```

**8 chips (2x2x2 topology):**
```bash
gcloud container node-pools create tpu-v6e-8chip \
  --cluster=YOUR_CLUSTER \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-8t \
  --tpu-topology=2x2x2 \
  --num-nodes=1
```

### TPU v5e - Cost-Effective Option

**4 chips:**
```bash
gcloud container node-pools create tpu-v5e-4chip \
  --cluster=YOUR_CLUSTER \
  --zone=us-central1-a \
  --machine-type=ct5e-standard-4 \
  --tpu-topology=2x2x1 \
  --num-nodes=1
```

### TPU v5p - High Performance

**4 chips:**
```bash
gcloud container node-pools create tpu-v5p-4chip \
  --cluster=YOUR_CLUSTER \
  --zone=us-central1-a \
  --machine-type=ct5p-hightpu-4t \
  --tpu-topology=2x2x1 \
  --num-nodes=1
```

## Machine Type Cheat Sheet

### TPU v6e Machine Types
| Machine Type | TPU Chips | vCPUs | Memory | Use Case |
|--------------|-----------|-------|--------|----------|
| ct6e-standard-1t | 1 | 44 | 176 GB | Development, small models |
| ct6e-standard-4t | 4 | 180 | 720 GB | **Most common** - training/inference |
| ct6e-standard-8t | 8 | 360 | 1440 GB | Large model training |
| ct6e-standard-16t | 16 | - | - | Distributed training |
| ct6e-standard-32t | 32 | - | - | Very large models |
| ct6e-standard-64t | 64 | - | - | Research/supercomputing |
| ct6e-standard-128t | 128 | - | - | Multi-node distributed |
| ct6e-standard-256t | 256 | - | - | Largest available |

### TPU v5e Machine Types
| Machine Type | TPU Chips | vCPUs | Memory | Use Case |
|--------------|-----------|-------|--------|----------|
| ct5e-standard-1 | 1 | 12 | 48 GB | Development |
| ct5e-standard-4 | 4 | 48 | 192 GB | **Most common** |
| ct5e-standard-8 | 8 | 96 | 384 GB | Medium-large models |
| ct5e-standard-16 | 16 | - | - | Large-scale training |

### TPU v5p Machine Types
| Machine Type | TPU Chips | vCPUs | Memory | Use Case |
|--------------|-----------|-------|--------|----------|
| ct5p-hightpu-1t | 1 | 208 | 832 GB | Development |
| ct5p-hightpu-4t | 4 | - | - | High-performance training |
| ct5p-hightpu-8t | 8 | - | - | Large models |

## TPU Topology Reference

The `--tpu-topology` flag defines how TPU chips are physically arranged.

**Format:** `X x Y x Z` (3D grid)

### Common Topologies

| Chip Count | Topology | Description |
|------------|----------|-------------|
| 1 | (omit flag) | Single chip, no topology needed |
| 4 | 2x2x1 | 2x2 grid (most common) |
| 8 | 2x2x2 | 2x2x2 cube |
| 8 | 4x2x1 | 4x2 grid (alternative) |
| 16 | 2x2x4 | Standard for 16 chips |
| 16 | 4x4x1 | 4x4 grid (alternative) |
| 32 | 4x4x2 | Standard for 32 chips |
| 64 | 4x4x4 | 4x4x4 cube |
| 128 | 8x8x2 | Standard for 128 chips |
| 256 | 8x8x4 | Standard for 256 chips |

### Rules
- **Product must equal chip count:** 2x2x1 = 4 chips
- **Must match machine type:** ct6e-standard-4t requires 4-chip topology
- **Single chip:** Don't specify --tpu-topology (defaults to 1x1x1)

## Zone Selection

Use the accelerator checker to find available zones:

```bash
# Find TPU v6e zones
./check-gke-accelerator-availability.sh --type tpu --api

# Validate specific zone
./check-gke-accelerator-availability.sh us-central1-b
```

**Recommended zones for TPU v6e:**
1. us-central1-b (Central US)
2. us-south1-a (Dallas)
3. us-east5-a (Columbus)

## Complete Example: Creating Cluster + TPU Node Pool

```bash
# 1. Create GKE cluster (in zone that supports TPUs)
gcloud container clusters create tpu-cluster \
  --zone=us-central1-b \
  --machine-type=n2-standard-4 \
  --num-nodes=2 \
  --enable-ip-alias

# 2. Create TPU node pool
gcloud container node-pools create tpu-v6e-pool \
  --cluster=tpu-cluster \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-4t \
  --tpu-topology=2x2x1 \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3

# 3. Get cluster credentials
gcloud container clusters get-credentials tpu-cluster --zone=us-central1-b

# 4. Verify TPU node pool
kubectl get nodes -o wide
```

## GPU vs TPU Node Pool Differences

### GPU Node Pools (for comparison)
```bash
# GPUs use --accelerator flag separate from machine type
gcloud container node-pools create gpu-pool \
  --cluster=my-cluster \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \          # Standard machine type
  --accelerator type=nvidia-tesla-t4,count=1 \  # Separate accelerator
  --num-nodes=1
```

### TPU Node Pools
```bash
# TPUs use special machine types (ct*) that INCLUDE the TPU
gcloud container node-pools create tpu-pool \
  --cluster=my-cluster \
  --zone=us-central1-b \
  --machine-type=ct6e-standard-4t \       # Machine type includes TPU!
  --tpu-topology=2x2x1 \                  # Topology for multi-chip
  --num-nodes=1
```

**Key Difference:**
- **GPU:** machine-type + --accelerator
- **TPU:** special machine-type (ct*) + --tpu-topology

## Common Issues

### Issue: "Machine type ct6e-standard-4t not available"
**Cause:** Zone doesn't support TPU v6e
**Solution:** Check zone availability:
```bash
./check-gke-accelerator-availability.sh --type tpu --api
```

### Issue: "Invalid topology 2x2x1 for machine type ct6e-standard-8t"
**Cause:** Topology chip count (2x2x1=4) doesn't match machine type (8 chips)
**Solution:** Use correct topology for 8 chips:
```bash
--machine-type=ct6e-standard-8t \
--tpu-topology=2x2x2  # 2x2x2 = 8 chips
```

### Issue: "Insufficient TPU quota"
**Cause:** Project quota limit reached
**Solution:** Request quota increase:
```bash
# Check current quota
gcloud compute project-info describe --project=YOUR_PROJECT

# Request increase via GCP Console:
# IAM & Admin → Quotas → Filter: "TPU v6e"
```

## Cost Optimization

**Autoscaling (recommended):**
```bash
gcloud container node-pools create tpu-pool \
  --machine-type=ct6e-standard-4t \
  --tpu-topology=2x2x1 \
  --enable-autoscaling \
  --min-nodes=0 \      # Scale to zero when not in use
  --max-nodes=3
```

**Manual scaling to zero:**
```bash
# Scale down to 0 nodes when not in use
gcloud container node-pools resize tpu-pool \
  --cluster=tpu-cluster \
  --zone=us-central1-b \
  --num-nodes=0

# Scale back up when needed
gcloud container node-pools resize tpu-pool \
  --cluster=tpu-cluster \
  --zone=us-central1-b \
  --num-nodes=1
```

## Additional Resources

- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/plan-tpus)
- [TPU System Architecture](https://cloud.google.com/tpu/docs/system-architecture-tpu-vm)
- [Machine Type Pricing](https://cloud.google.com/compute/vm-instance-pricing#machine-types)

## Quick Decision Tree

```
Need TPU for GKE?
│
├─ Development/Testing?
│  └─ Use: ct6e-standard-1t (single chip, cheapest)
│
├─ Production Training?
│  └─ Use: ct6e-standard-4t with --tpu-topology=2x2x1 (most common)
│
├─ Large Model Training?
│  └─ Use: ct6e-standard-8t with --tpu-topology=2x2x2
│
└─ Budget Constrained?
   └─ Use: ct5e-standard-4 with --tpu-topology=2x2x1 (v5e is cheaper)
```
