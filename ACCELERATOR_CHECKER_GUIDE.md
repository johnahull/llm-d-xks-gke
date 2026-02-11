# GKE Accelerator Availability Checker Guide

## Overview

The `check-gke-accelerator-availability.sh` script provides unified checking of both TPU and GPU availability across GKE zones. It supersedes the TPU-only checker with enhanced filtering and validation capabilities.

## Quick Start

```bash
# Show all accelerators (fast, hardcoded data)
./check-gke-accelerator-availability.sh

# Show all accelerators (live API data, always current)
./check-gke-accelerator-availability.sh --api

# Show only GPUs in us-central1
./check-gke-accelerator-availability.sh --type gpu --region us-central1

# Show live GPU data (may find more zones)
./check-gke-accelerator-availability.sh --api --type gpu --region us-central1

# Validate a specific zone
./check-gke-accelerator-availability.sh us-central1-a

# Show help
./check-gke-accelerator-availability.sh --help
```

## Data Source Options

### Hardcoded Data (Default)
- **Speed:** Instant
- **Data freshness:** Updated Feb 2026
- **Pros:** No authentication required, works offline, consistent results
- **Cons:** May become stale as Google adds new zones
- **Zone counts:** T4: 22, A100: 13, L4: 13, H100: 8

### Live API Data (--api flag)
- **Speed:** 10-20 seconds
- **Data freshness:** Real-time from Google Cloud
- **Pros:** Always current, discovers new zones as they become available
- **Cons:** Requires gcloud authentication, slower, needs network access
- **Zone counts (as of Feb 2026):** T4: 51, A100: 22, L4: 45, H100: 31

**Recommendation:** Use default mode for quick checks and planning. Use `--api` when accuracy is critical or you suspect data is outdated.

## Supported Accelerators

### TPUs
- **v6e (Trillium)** - Latest generation, 9 zones
- **v5e** - Wider availability, 5 zones
- **v5p** - High performance, 3 zones

### GPUs
- **NVIDIA T4** - Cost-effective, 22 zones (⭐ us-central1-a currently used)
- **NVIDIA A100** - Premium, 13 zones
- **NVIDIA L4** - Efficient, 13 zones
- **NVIDIA H100** - Latest, 8 zones

## Command-Line Options

### Filtering Options

| Option | Values | Description |
|--------|--------|-------------|
| `--type` | `tpu`, `gpu`, `all` | Filter by accelerator type (default: all) |
| `--region` | Pattern | Filter by region (e.g., "us-central1", "us-*") |
| `--zone` | Zone name | Validate specific zone |
| `--api` | - | Fetch live data from Google Cloud API (slower but always current) |
| `--help` | - | Show help message |

### Positional Arguments

```bash
./check-gke-accelerator-availability.sh <zone>
# Same as: --zone <zone>
```

## Using API Mode

### When to Use --api

Use the `--api` flag when:
- You need the most up-to-date zone information
- Planning a new deployment and want to see all available options
- Hardcoded data seems outdated or incomplete
- Investigating why a zone isn't listed in default mode

### Requirements for API Mode

1. **gcloud CLI installed:**
   ```bash
   # Check if gcloud is installed
   gcloud --version
   ```

2. **Authenticated to Google Cloud:**
   ```bash
   # Authenticate if needed
   gcloud auth login

   # Set the project
   gcloud config set project ecoeng-llmd
   ```

3. **Appropriate IAM permissions:**
   - `compute.acceleratorTypes.list` permission
   - Typically granted via `Compute Viewer` role or higher

### API Mode Performance

```bash
# Typical execution times:
--api --type gpu          # ~5-8 seconds (4 API calls)
--api --type tpu          # ~3-5 seconds (3 API calls)
--api (all accelerators)  # ~10-15 seconds (7 API calls)
```

### API Data Differences

The API often reveals **significantly more zones** than hardcoded data:

| Accelerator | Hardcoded | API (Feb 2026) | Difference |
|-------------|-----------|----------------|------------|
| T4 GPU      | 22 zones  | 51 zones       | +132% |
| A100 GPU    | 13 zones  | 22 zones       | +69% |
| L4 GPU      | 13 zones  | 45 zones       | +246% |
| H100 GPU    | 8 zones   | 31 zones       | +288% |
| TPU v6e     | 9 zones   | ~9 zones       | Similar |
| TPU v5e     | 5 zones   | ~5 zones       | Similar |

**Key insight:** GPU availability is expanding rapidly, making API mode valuable for finding new deployment options.

## Examples

### Using API Mode

```bash
# Fetch live data for all accelerators
./check-gke-accelerator-availability.sh --api

# Find all current GPU zones (slow but comprehensive)
./check-gke-accelerator-availability.sh --api --type gpu

# Check latest TPU availability in Europe
./check-gke-accelerator-availability.sh --api --type tpu --region "europe-*"

# Discover all H100 zones worldwide
./check-gke-accelerator-availability.sh --api --type gpu | grep -A50 "H100"
```

### Filter by Type

```bash
# Show only GPU zones
./check-gke-accelerator-availability.sh --type gpu

# Show only TPU zones
./check-gke-accelerator-availability.sh --type tpu
```

### Filter by Region

```bash
# Exact region match
./check-gke-accelerator-availability.sh --region us-central1

# Wildcard patterns
./check-gke-accelerator-availability.sh --region "us-*"
./check-gke-accelerator-availability.sh --region "europe-*"
```

### Combined Filters

```bash
# GPUs in us-central1
./check-gke-accelerator-availability.sh --type gpu --region us-central1

# TPUs in US regions
./check-gke-accelerator-availability.sh --type tpu --region "us-*"
```

### Zone Validation

```bash
# Validate all accelerators in zone
./check-gke-accelerator-availability.sh us-central1-a

# Validate only GPUs in zone
./check-gke-accelerator-availability.sh --type gpu --zone us-central1-a

# Validate only TPUs in zone
./check-gke-accelerator-availability.sh --type tpu us-east5-a
```

## Output Format

### Zone Listing

```
NVIDIA T4 GPU Supported Zones in GKE:
----------------------------------------
  us-central1-a        US Central ⭐
  us-central1-b        US Central
  us-central1-c        US Central
```

- **⭐** indicates currently used zones (us-central1-a for T4 GPU)
- Zones are sorted alphabetically
- Filtered zones show "(No zones match the filter)"

### Zone Validation

```
✅ NVIDIA T4 GPU is SUPPORTED in us-central1-a
   Region: US Central ⭐
   Machine types: n1-standard-* with --accelerator type=nvidia-tesla-t4

✅ GKE is available in us-central1-a
   Latest GKE version: 1.34.3-gke.1051003
```

## Currently Used Zones

The script highlights zones currently used in deployments:

- **us-central1-a** (T4 GPU) ⭐
  - Pattern 1 (gateway-api/pattern1-baseline)
  - Pattern 2 (gateway-api/pattern2-multimodel)
  - Pattern 3 (gateway-api/pattern3-caching)

## Migration from Old Script

The original `check-gke-tpu-availability.sh` remains available for backward compatibility:

```bash
# Old script (TPU only)
./check-gke-tpu-availability.sh us-central1-a

# New script (equivalent)
./check-gke-accelerator-availability.sh --type tpu us-central1-a
```

## Integration with Deployments

Use the script to plan deployments:

```bash
# Check GPU availability for Pattern 1 deployment
./check-gke-accelerator-availability.sh --type gpu --region us-central1

# Find TPU zones for KServe deployment
./check-gke-accelerator-availability.sh --type tpu --region us-east5

# Validate zone before creating cluster
./check-gke-accelerator-availability.sh us-central1-a
```

## Technical Details

### Zone Data Sources

- TPU zones: [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/plan-tpus)
- GPU zones: Compiled from GKE availability matrix (as of Feb 2026)

### GKE Availability Check

The script validates GKE availability using:
```bash
gcloud container get-server-config --zone=$ZONE --project=$PROJECT
```

Requires:
- `gcloud` CLI installed
- Authenticated to project `ecoeng-llmd`
- Appropriate IAM permissions

### No API Calls for Zone Listing

Zone data is hardcoded for reliability:
- Faster than API calls
- Works offline
- No quota concerns
- Consistent results

## Troubleshooting

### Script Not Executable

```bash
chmod +x check-gke-accelerator-availability.sh
```

### GKE Availability Check Fails

Ensure you're authenticated:
```bash
gcloud auth login
gcloud config set project ecoeng-llmd
```

### No Zones Match Filter

Check your region pattern:
```bash
# Incorrect (too specific)
--region us-central1-a

# Correct (region prefix)
--region us-central1
```

## Future Enhancements

Potential improvements (not currently implemented):

- Live API integration for zone availability
- Cost estimation per zone
- Quota checking
- Performance benchmarks by zone
- Multi-zone deployment planning
