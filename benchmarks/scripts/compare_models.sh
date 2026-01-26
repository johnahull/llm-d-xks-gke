#!/bin/bash
# Compare multiple models on the same deployment target
# Usage: ./compare_models.sh [target] [scenario]
# Examples:
#   ./compare_models.sh tpu-v6e latency_benchmark
#   ./compare_models.sh gke-t4 quick_validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
VENV_PATH="/home/jhull/devel/venv"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Activate venv if available
if [ -f "$VENV_PATH/bin/activate" ]; then
    source "$VENV_PATH/bin/activate"
fi

# Parse arguments
TARGET=${1:-"tpu-v6e"}
SCENARIO=${2:-"latency_benchmark"}
OUTPUT_DIR="$BENCHMARK_DIR/results/model_comparison_$(date +%Y%m%d_%H%M%S)"

echo -e "${BLUE}========================================"
echo "  Multi-Model Comparison Benchmark"
echo "========================================${NC}"
echo "Target: $TARGET"
echo "Scenario: $SCENARIO"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run multi-model benchmark
echo -e "${BLUE}Running benchmark on all supported models...${NC}"
echo ""

python3 "$BENCHMARK_DIR/python/benchmark_async.py" \
    --target "$TARGET" \
    --scenario "$SCENARIO" \
    --all-models \
    --output "$OUTPUT_DIR/results.json" \
    --html

BENCHMARK_STATUS=$?

if [ $BENCHMARK_STATUS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================"
    echo "  Multi-Model Benchmark Complete"
    echo "========================================${NC}"
    echo "Results saved to: $OUTPUT_DIR"
    echo ""
    echo "View results:"
    echo "  - JSON comparison: $OUTPUT_DIR/results_comparison.json"
    echo "  - HTML comparison: $OUTPUT_DIR/results_comparison.html"
    echo "  - Individual model JSONs: $OUTPUT_DIR/results_*.json"
else
    echo ""
    echo -e "${YELLOW}========================================"
    echo "  Benchmark completed with warnings"
    echo "========================================${NC}"
    echo "Check results in: $OUTPUT_DIR"
fi

exit $BENCHMARK_STATUS
