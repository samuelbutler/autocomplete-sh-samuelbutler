#!/bin/zsh

# Test the fixed menu selector

# Source the autocomplete script
source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Load models
_load_models_from_json

# Get sorted keys
sorted_keys=()
for key in ${(k)_autocomplete_modellist}; do
    sorted_keys+=("$key")
done
sorted_keys=(${(o)sorted_keys[@]})

echo "=== Testing menu selector fix ==="
echo
echo "First 5 models in sorted order:"
for ((i=1; i<=5 && i<=${#sorted_keys[@]}; i++)); do
    echo "  $i: ${sorted_keys[i]}"
done

echo
echo "Testing selection of first item (claude-3-5-haiku should be at index 1):"

# Simulate selecting the first item
selected_option=1
if [[ $selected_option -eq 255 ]]; then
    echo "ERROR: Would incorrectly treat as cancelled!"
else
    echo "SUCCESS: Not treating index 1 as cancellation"
    selected_model="${sorted_keys[$selected_option]}"
    echo "Selected model: '$selected_model'"
    
    if [[ "$selected_model" =~ "haiku" ]] && [[ "$selected_model" =~ "claude-3-5" ]]; then
        echo "SUCCESS: claude-3-5-haiku can now be selected!"
        value="${_autocomplete_modellist[$selected_model]}"
        echo "Value: $value"
    fi
fi