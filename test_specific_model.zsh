#!/bin/zsh

# Test selecting claude-3-5-haiku specifically

source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Load models
_load_models_from_json

# Build the key for claude-3-5-haiku
provider="anthropic"
model_name="claude-3-5-haiku-20241022"
key=$(printf "%s:\t%s" "$provider" "$model_name")

echo "Looking for key: '$key'"
echo "Key hex: "
echo -n "$key" | xxd -p

# Check if it exists in the array
if [[ -n "${_autocomplete_modellist[$key]}" ]]; then
    echo "Found in array!"
    echo "Value: ${_autocomplete_modellist[$key]}"
else
    echo "NOT found in array!"
    
    # Let's see what keys contain haiku
    echo -e "\nKeys containing 'haiku':"
    for k in "${(@k)_autocomplete_modellist}"; do
        if [[ "$k" =~ "haiku" ]]; then
            echo "  Key: '$k'"
            echo -n "  Hex: "
            echo -n "$k" | xxd -p
            echo ""
        fi
    done
fi