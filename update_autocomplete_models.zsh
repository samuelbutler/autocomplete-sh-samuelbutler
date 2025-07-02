#!/bin/zsh
# update_autocomplete_models.zsh - Update autocomplete.zsh with models from JSON file

set -euo pipefail

# Color functions
echo_green() {
    echo -e "\e[32m$1\e[0m"
}

echo_error() {
    echo -e "\e[31m$1\e[0m" >&2
}

# Default paths
MODELS_FILE="${1:-$HOME/.autocomplete/models.json}"
AUTOCOMPLETE_FILE="/Users/sambutler/.local/bin/autocomplete.zsh"

# Check if files exist
if [[ ! -f "$MODELS_FILE" ]]; then
    echo_error "Error: Models file not found: $MODELS_FILE"
    echo "Run 'get_autocomplete_models.zsh' first to fetch models."
    exit 1
fi

if [[ ! -f "$AUTOCOMPLETE_FILE" ]]; then
    echo_error "Error: autocomplete.zsh not found: $AUTOCOMPLETE_FILE"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo_error "Error: jq is required but not installed."
    exit 1
fi

# Generate model list entry
generate_model_entry() {
    local model="$1"
    
    local provider=$(echo "$model" | jq -r '.provider')
    local model_name=$(echo "$model" | jq -r '.model')
    local endpoint=$(echo "$model" | jq -r '.endpoint')
    local prompt_cost=$(echo "$model" | jq -r '.prompt_cost')
    local completion_cost=$(echo "$model" | jq -r '.completion_cost')
    
    # Format the key with tab for consistency
    local key="${provider}:	${model_name}"
    
    # Generate the JSON value (already formatted correctly in the JSON file)
    local value=$(echo "$model" | jq -c '.')
    
    echo "_autocomplete_modellist['$key']='$value'"
}

# Main update function
main() {
    echo_green "Updating autocomplete.zsh with models from $MODELS_FILE"
    
    # Read the models file
    local models_json=$(cat "$MODELS_FILE")
    local timestamp=$(echo "$models_json" | jq -r '.timestamp')
    local model_count=$(echo "$models_json" | jq '.models | length')
    
    echo "Models file timestamp: $timestamp"
    echo "Total models: $model_count"
    
    # Create temporary file for the new model list
    local temp_file="/tmp/autocomplete_models_$$.tmp"
    
    {
        echo "typeset -A _autocomplete_modellist"
        
        # Group models by provider
        local providers=($(echo "$models_json" | jq -r '.models[].provider' | sort -u))
        
        for provider in "${providers[@]}"; do
            echo "# ${provider^} models"
            
            # Get models for this provider
            local provider_models=$(echo "$models_json" | jq -c ".models[] | select(.provider == \"$provider\")")
            
            while IFS= read -r model; do
                if [[ -n "$model" ]]; then
                    generate_model_entry "$model"
                fi
            done <<< "$provider_models"
        done
    } > "$temp_file"
    
    # Create a backup
    cp "$AUTOCOMPLETE_FILE" "${AUTOCOMPLETE_FILE}.bak"
    echo "Created backup: ${AUTOCOMPLETE_FILE}.bak"
    
    # Find the line numbers for the model list section
    local start_line=$(grep -n "^typeset -A _autocomplete_modellist" "$AUTOCOMPLETE_FILE" | cut -d: -f1)
    local end_line=$(awk -v start="$start_line" 'NR > start && /^###/ {print NR-1; exit}' "$AUTOCOMPLETE_FILE")
    
    if [[ -z "$start_line" || -z "$end_line" ]]; then
        echo_error "Error: Could not find model list section in autocomplete.zsh"
        rm "$temp_file"
        exit 1
    fi
    
    # Build the new file
    {
        head -n $((start_line - 1)) "$AUTOCOMPLETE_FILE"
        cat "$temp_file"
        echo ""
        tail -n +$((end_line + 1)) "$AUTOCOMPLETE_FILE"
    } > "${AUTOCOMPLETE_FILE}.new"
    
    # Replace the original file
    mv "${AUTOCOMPLETE_FILE}.new" "$AUTOCOMPLETE_FILE"
    chmod +x "$AUTOCOMPLETE_FILE"
    
    rm "$temp_file"
    
    echo_green "Successfully updated autocomplete.zsh!"
    echo "Run 'autocomplete model' to see the updated list."
}

# Run main
main "$@"