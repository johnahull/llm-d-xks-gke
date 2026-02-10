# API Access Guide - Pattern 1 Istio/KServe

## OpenAI-Compatible API Endpoints

The Qwen2.5-3B-Instruct model is accessible via the Istio gateway at:

**Base URL:** `http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1`

## Available Endpoints

### 1. List Models
```bash
curl -s http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models | jq .
```

### 2. Text Completions
```bash
curl -X POST http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"What is the capital of France?","max_tokens":50}' | jq .
```

**Example Response:**
```json
{
  "id": "cmpl-e603606f-0cfe-4294-9dab-de94203805fd",
  "object": "text_completion",
  "created": 1770757332,
  "model": "/mnt/models",
  "choices": [{
    "index": 0,
    "text": " The capital of France is Paris. Paris is a beautiful city known for its art, fashion, cuisine",
    "finish_reason": "length"
  }],
  "usage": {
    "prompt_tokens": 7,
    "total_tokens": 27,
    "completion_tokens": 20
  }
}
```

### 3. Chat Completions
```bash
curl -X POST http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","messages":[{"role":"user","content":"Hello, how can you help me?"}],"max_tokens":50}' | jq .
```

**Example Response:**
```json
{
  "id": "chatcmpl-9dd7c092-a950-45c1-a6cb-fca0a87dd004",
  "object": "chat.completion",
  "created": 1770757335,
  "model": "/mnt/models",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello, how can I help you?"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 35,
    "total_tokens": 44,
    "completion_tokens": 9
  }
}
```

## Python Client Example

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/v1",
    api_key="dummy"  # vLLM doesn't require authentication
)

# Chat completion
response = client.chat.completions.create(
    model="/mnt/models",
    messages=[
        {"role": "user", "content": "What is Kubernetes?"}
    ],
    max_tokens=100
)

print(response.choices[0].message.content)
```

## Model Information

- **Model:** Qwen2.5-3B-Instruct
- **Max Context Length:** 2048 tokens
- **Tensor Parallelism:** 4-way (TPU v6e-4)
- **Precision:** FP16 (half)
- **Backend:** vLLM on Google Cloud TPU

## Health Check

```bash
curl http://34.7.208.8/llm-d-inference-scheduling/qwen2-3b-pattern1/health
```

## Notes

- The API is compatible with OpenAI's client libraries
- No authentication is currently required (PoC setup)
- The gateway IP (34.7.208.8) is the Istio ingress gateway external IP
- All requests are routed through the Istio service mesh
