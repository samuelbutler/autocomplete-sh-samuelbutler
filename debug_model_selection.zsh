#!/bin/zsh

# Debug script to test model selection issue with claude-3-5-haiku

# Load the models.json file
models_file="$HOME/.autocomplete/models.json"
models_json=$(cat "$models_file" 2>/dev/null)

# Parse all models
echo "Parsing models..."
parsed_models=$(echo "$models_json" | jq -r '.models[] | "\(.provider)|\(.model)|\(.endpoint)|\(.prompt_cost)|\(.completion_cost)"' 2>/dev/null)

# Look for claude-3-5-haiku specifically
echo -e "\nSearching for claude-3-5-haiku models:"
echo "$parsed_models" | grep "claude-3-5-haiku"

# Build the key for claude-3-5-haiku
echo -e "\nBuilding key for claude-3-5-haiku-20241022:"
provider="anthropic"
model="claude-3-5-haiku-20241022"
key=$(printf "%s:\t%s" "$provider" "$model")
echo "Key: '$key'"

# Test jq extraction of the model value
echo -e "\nTesting JSON extraction:"
model_json='{"model":"claude-3-5-haiku-20241022","provider":"anthropic","endpoint":"https://api.anthropic.com/v1/messages","prompt_cost":2.5e-07,"completion_cost":1.25e-06}'
echo "Model JSON: $model_json"
model_name=$(echo "$model_json" | jq -r '.model')
echo "Extracted model name: '$model_name'"

# Test sed replacement
echo -e "\nTesting sed replacement:"
test_config="model: old-model"
echo "Before: $test_config"
new_config=$(echo "$test_config" | sed "s|^\(model:\).*|\1 claude-3-5-haiku-20241022|")
echo "After: $new_config"

# Check if there's an issue with the model name in sed
echo -e "\nTesting with escaped model name:"
escaped_model=$(printf '%s\n' "$model_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
echo "Escaped model: '$escaped_model'"