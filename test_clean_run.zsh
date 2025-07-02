#!/bin/zsh

# Test a clean run without debug output

# Source the script but redirect stderr to null to avoid debug output
source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh 2>/dev/null

# Reset models
_autocomplete_models_loaded=0

# Load models explicitly
_load_models_from_json 2>/dev/null

# Test direct lookup first
echo "Testing direct lookup..."
provider="anthropic"
model_name="claude-3-5-haiku-20241022"
key=$(printf "%s:\t%s" "$provider" "$model_name")
value="${_autocomplete_modellist[$key]}"

if [[ -n "$value" ]]; then
    echo "Direct lookup works! Value found."
else
    echo "Direct lookup failed!"
fi

# Now run the model command
echo -e "\nRunning autocomplete model command..."
autocomplete model anthropic claude-3-5-haiku-20241022