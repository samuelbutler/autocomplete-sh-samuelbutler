#!/bin/zsh

# Test the model loading logic from autocomplete.zsh

typeset -A _autocomplete_modellist

# Load models from JSON file
models_file="$HOME/.autocomplete/models.json"
models_json=$(cat "$models_file" 2>/dev/null)

# Parse all models at once using jq
parsed_models=$(echo "$models_json" | jq -r '.models[] | "\(.provider)|\(.model)|\(.endpoint)|\(.prompt_cost)|\(.completion_cost)"' 2>/dev/null)

# Process each model
echo "Loading models..."
while IFS='|' read -r provider model endpoint prompt_cost completion_cost; do
    # Skip if essential fields are missing
    if [[ -z "$provider" || -z "$model" || -z "$endpoint" ]]; then
        continue
    fi
    
    # Format the key with appropriate spacing
    local key
    if [[ "$provider" == "groq" ]]; then
        key=$(printf "%s:\t\t%s" "$provider" "$model")
    else
        key=$(printf "%s:\t%s" "$provider" "$model")
    fi
    
    # Create the value JSON inline
    local value="{ \"model\": \"$model\", \"provider\": \"$provider\", \"endpoint\": \"$endpoint\", \"prompt_cost\": $prompt_cost, \"completion_cost\": $completion_cost }"
    
    # Store in the associative array
    _autocomplete_modellist["$key"]="$value"
    
    # Debug: show what we stored for claude-3-5-haiku
    if [[ "$model" =~ "claude-3-5-haiku" ]]; then
        echo "Found claude-3-5-haiku:"
        echo "  Key: '$key'"
        echo "  Value: $value"
    fi
done <<< "$parsed_models"

echo -e "\nAll anthropic models:"
for key in ${(k)_autocomplete_modellist}; do
    if [[ "$key" =~ "anthropic" ]]; then
        echo "  Key: '$key'"
        # Show the hex dump of the key to see the actual characters
        echo -n "  Hex: "
        echo -n "$key" | xxd -p
    fi
done

# Test lookup
echo -e "\nTesting lookup for anthropic:	claude-3-5-haiku-20241022"
test_key=$(printf "%s:\t%s" "anthropic" "claude-3-5-haiku-20241022")
echo "Test key: '$test_key'"
echo "Value: ${_autocomplete_modellist[$test_key]}"