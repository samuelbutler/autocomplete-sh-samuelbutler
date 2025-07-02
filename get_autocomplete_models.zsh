#!/bin/zsh
# get_autocomplete_models.zsh - Fetch available models from OpenAI and Anthropic APIs
# and save them to a JSON file

set -euo pipefail

# Color functions
echo_green() {
    echo -e "\e[32m$1\e[0m"
}

echo_error() {
    echo -e "\e[31m$1\e[0m" >&2
}

echo_yellow() {
    echo -e "\e[33m$1\e[0m"
}

# Default output file
OUTPUT_FILE="${1:-$HOME/.autocomplete/models.json}"

# Check for required tools
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo_error "Error: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
}

# Load API keys from environment or config
load_api_keys() {
    local config_file="$HOME/.autocomplete/config"
    
    # Try to load from config file first
    if [[ -f "$config_file" ]]; then
        # Extract API keys from config
        if [[ -z "${OPENAI_API_KEY:-}" ]]; then
            local config_key=$(grep "^openai_api_key:" "$config_file" | cut -d' ' -f2-)
            if [[ "$config_key" != '$OPENAI_API_KEY' && -n "$config_key" ]]; then
                OPENAI_API_KEY="$config_key"
            fi
        fi
        if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
            local config_key=$(grep "^anthropic_api_key:" "$config_file" | cut -d' ' -f2-)
            if [[ "$config_key" != '$ANTHROPIC_API_KEY' && -n "$config_key" ]]; then
                ANTHROPIC_API_KEY="$config_key"
            fi
        fi
    fi
    
    # Check if keys are set
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo_yellow "Warning: OPENAI_API_KEY not set. Skipping OpenAI models."
    fi
    
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo_yellow "Warning: ANTHROPIC_API_KEY not set. Skipping Anthropic models."
    fi
    
    if [[ -z "${OPENAI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo_error "Error: No API keys found. Please set OPENAI_API_KEY and/or ANTHROPIC_API_KEY"
        exit 1
    fi
}

# Default cost structure for models
get_model_cost() {
    local provider="$1"
    local model="$2"
    
    # Default costs per million tokens
    local prompt_cost="0.0000030"
    local completion_cost="0.0000150"
    
    case "$provider" in
        "openai")
            # Set all OpenAI model costs to zero
            prompt_cost="0"
            completion_cost="0"
            ;;
        "anthropic")
            case "$model" in
                *"haiku"*) 
                    prompt_cost="0.00000025"
                    completion_cost="0.00000125"
                    ;;
                *"sonnet-4"*|*"claude-3-7-sonnet"*) 
                    # Claude 4 Sonnet and 3.7 Sonnet pricing
                    prompt_cost="0.0000030"
                    completion_cost="0.0000150"
                    ;;
                *"sonnet"*) 
                    prompt_cost="0.0000030"
                    completion_cost="0.0000150"
                    ;;
                *"opus-4"*) 
                    # Claude 4 Opus pricing
                    prompt_cost="0.0000150"
                    completion_cost="0.0000750"
                    ;;
                *"opus"*) 
                    prompt_cost="0.0000150"
                    completion_cost="0.0000750"
                    ;;
            esac
            ;;
    esac
    
    echo "$prompt_cost $completion_cost"
}

# Fetch OpenAI models
fetch_openai_models() {
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "[]"
        return 0
    fi
    
    echo_green "Fetching OpenAI models..." >&2
    
    local response
    response=$(curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
        https://api.openai.com/v1/models)
    
    if [[ $? -ne 0 ]]; then
        echo_error "Failed to fetch OpenAI models"
        echo "[]"
        return
    fi
    
    # Check for API error
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo_error "OpenAI API error: $(echo "$response" | jq -r '.error.message')"
        echo "[]"
        return
    fi
    
    # Extract model IDs that are suitable for chat completions
    # Filter for gpt, o1, and o3 models
    local models=$(echo "$response" | jq -r '.data[] | select(.id | test("^(gpt|o1|o3)")) | .id' | sort -u)
    
    # Build JSON array of model objects
    local json_array="[]"
    while IFS= read -r model; do
        if [[ -n "$model" ]]; then
            local costs=($(get_model_cost "openai" "$model"))
            local prompt_cost="${costs[1]}"
            local completion_cost="${costs[2]}"
            
            local model_obj=$(jq -n \
                --arg model "$model" \
                --arg provider "openai" \
                --arg endpoint "https://api.openai.com/v1/chat/completions" \
                --arg prompt_cost "$prompt_cost" \
                --arg completion_cost "$completion_cost" \
                '{
                    model: $model,
                    provider: $provider,
                    endpoint: $endpoint,
                    prompt_cost: ($prompt_cost | tonumber),
                    completion_cost: ($completion_cost | tonumber)
                }')
            
            json_array=$(echo "$json_array" | jq ". += [$model_obj]")
        fi
    done <<< "$models"
    
    echo "$json_array"
}

# Fetch Anthropic models
fetch_anthropic_models() {
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "[]"
        return 0
    fi
    
    echo_green "Fetching Anthropic models..." >&2
    
    local response
    response=$(curl -s -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        https://api.anthropic.com/v1/models)
    
    if [[ $? -ne 0 ]]; then
        echo_error "Failed to fetch Anthropic models"
        echo "[]"
        return
    fi
    
    # Check for API error
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo_error "Anthropic API error: $(echo "$response" | jq -r '.error.message')"
        echo "[]"
        return
    fi
    
    # Extract model IDs
    local models=$(echo "$response" | jq -r '.data[] | .id' | sort -u)
    
    # Build JSON array of model objects
    local json_array="[]"
    while IFS= read -r model; do
        if [[ -n "$model" ]]; then
            local costs=($(get_model_cost "anthropic" "$model"))
            local prompt_cost="${costs[1]}"
            local completion_cost="${costs[2]}"
            
            local model_obj=$(jq -n \
                --arg model "$model" \
                --arg provider "anthropic" \
                --arg endpoint "https://api.anthropic.com/v1/messages" \
                --arg prompt_cost "$prompt_cost" \
                --arg completion_cost "$completion_cost" \
                '{
                    model: $model,
                    provider: $provider,
                    endpoint: $endpoint,
                    prompt_cost: ($prompt_cost | tonumber),
                    completion_cost: ($completion_cost | tonumber)
                }')
            
            json_array=$(echo "$json_array" | jq ". += [$model_obj]")
        fi
    done <<< "$models"
    
    echo "$json_array"
}

# Get static models (Groq, Ollama)
get_static_models() {
    cat <<'EOF'
[
    {
        "model": "llama3-8b-8192",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama3-70b-8192",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-3.3-70b-versatile",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-3.1-8b-instant",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-guard-3-8b",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "mixtral-8x7b-32768",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "gemma2-9b-it",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "mistral-saba-24b",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "qwen-2.5-coder-32b",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "deepseek-r1-distill-qwen-32b",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "deepseek-r1-distill-llama-70b-specdec",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-3.3-70b-specdec",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-3.2-1b-preview",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "llama-3.2-3b-preview",
        "provider": "groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "prompt_cost": 0,
        "completion_cost": 0
    },
    {
        "model": "codellama",
        "provider": "ollama",
        "endpoint": "http://localhost:11434/api/chat",
        "prompt_cost": 0,
        "completion_cost": 0
    }
]
EOF
}

# Main function
main() {
    echo_green "Autocomplete Models Fetcher"
    echo "==========================="
    echo "Output file: $OUTPUT_FILE"
    echo ""
    
    check_dependencies
    load_api_keys
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    
    # Fetch models from all sources
    local openai_models=$(fetch_openai_models || echo "[]")
    local anthropic_models=$(fetch_anthropic_models || echo "[]")
    local static_models=$(get_static_models || echo "[]")
    
    # Combine all models into a single JSON object
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local all_models=$(jq -n \
        --arg timestamp "$timestamp" \
        --argjson openai "$openai_models" \
        --argjson anthropic "$anthropic_models" \
        --argjson static "$static_models" \
        '{
            "timestamp": $timestamp,
            "models": ($openai + $anthropic + $static)
        }')
    
    # Save to file
    if [[ -n "$all_models" ]]; then
        echo "$all_models" | jq '.' > "$OUTPUT_FILE"
        
        echo ""
        echo_green "Successfully saved models to $OUTPUT_FILE"
        echo "Total models: $(echo "$all_models" | jq '.models | length')"
        echo ""
        echo "Model count by provider:"
        echo "$all_models" | jq -r '.models | group_by(.provider) | .[] | "\(.[0].provider): \(length)"' || true
    else
        echo_error "Error: Failed to generate models JSON"
        exit 1
    fi
}

# Run main function
main "$@"