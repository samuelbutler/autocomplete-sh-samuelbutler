#!/bin/zsh

# Manually test the model command flow

source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Reset models to force reload
_autocomplete_models_loaded=0

# Load models
echo "Loading models..."
_load_models_from_json

# Now test the direct lookup
provider="anthropic"
model_name="claude-3-5-haiku-20241022"
key=$(printf "%s:\t%s" "$provider" "$model_name")

echo "Looking for key: '$key'"
echo -n "Key hex: "
echo -n "$key" | xxd -p

echo -e "\nChecking if key exists in array..."
if [[ -n "${_autocomplete_modellist[$key]}" ]]; then
    echo "Found!"
    echo "Value: ${_autocomplete_modellist[$key]}"
else
    echo "Not found!"
    
    echo -e "\nAll anthropic keys:"
    for k in ${(k)_autocomplete_modellist}; do
        if [[ "$k" =~ "anthropic.*haiku" ]]; then
            echo "  Key: '$k'"
            echo -n "  Hex: "
            echo -n "$k" | xxd -p
        fi
    done
fi