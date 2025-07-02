#!/bin/zsh

source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Load models
_load_models_from_json

# Try to find haiku models
echo "All keys in the array:"
for k in ${(k)_autocomplete_modellist}; do
    if [[ "$k" =~ "haiku" ]]; then
        echo "Raw key: $k"
        # Remove quotes
        clean_key="${k%\"}"
        clean_key="${clean_key#\"}"
        echo "Clean key: $clean_key"
        
        # Try to access with clean key
        echo "Value with clean key: ${_autocomplete_modellist[$clean_key]}"
        
        # Try to access with raw key
        echo "Value with raw key: ${_autocomplete_modellist[$k]}"
        echo "---"
    fi
done