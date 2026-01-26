#!/bin/bash
# Apache Bench benchmark for any OpenAI-compatible LLM API
# Supports: vLLM, Ollama, LM Studio, OpenAI API, and more
#
# Usage: ./ab_benchmark.sh [base_url] [num_requests] [concurrency] [model_name]
# Examples:
#   ./ab_benchmark.sh http://localhost:8000 100 10 google/gemma-2b-it
#   ./ab_benchmark.sh http://localhost:11434 50 5 llama3.2:3b
#   ./ab_benchmark.sh http://35.214.154.17 200 20 Qwen/Qwen2.5-3B-Instruct

BASE_URL=${1:-"http://35.214.154.17"}
NUM_REQUESTS=${2:-100}
CONCURRENCY=${3:-10}
MODEL=${4:-"Qwen/Qwen2.5-3B-Instruct"}

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================"
echo "  Apache Bench LLM API Benchmark"
echo "========================================${NC}"
echo "Target: $BASE_URL"
echo "Model: $MODEL"
echo "Total requests: $NUM_REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo ""

# Check if ab is installed
if ! command -v ab &> /dev/null; then
    echo "Error: Apache Bench (ab) not found"
    echo "Install with: sudo apt-get install apache2-utils"
    exit 1
fi

# Create results directory
RESULTS_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")/results"
mkdir -p "$RESULTS_DIR"

# Create temporary POST data file
TMP_FILE=$(mktemp)
cat > "$TMP_FILE" << EOF
{
  "model": "$MODEL",
  "prompt": "Write a short story about a robot learning to paint:",
  "max_tokens": 100,
  "temperature": 0.7
}
EOF

# Generate output file names
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TSV_FILE="$RESULTS_DIR/ab_results_${TIMESTAMP}.tsv"

# Run Apache Bench
echo "Running benchmark..."
echo ""

ab -n "$NUM_REQUESTS" \
   -c "$CONCURRENCY" \
   -p "$TMP_FILE" \
   -T "application/json" \
   -g "$TSV_FILE" \
   "$BASE_URL/v1/completions"

# Cleanup
rm "$TMP_FILE"

echo ""
echo -e "${GREEN}========================================"
echo "  Benchmark Complete"
echo "========================================${NC}"
echo "Results saved to:"
echo "  $TSV_FILE"
echo ""
echo "To analyze results:"
echo "  cat $TSV_FILE"
echo "  # or import into spreadsheet/plotting tool"
