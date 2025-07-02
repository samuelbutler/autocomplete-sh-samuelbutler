#!/bin/zsh

# Set debug mode
export DEBUG_AUTOCOMPLETE=1

# Source the autocomplete script
source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Load models
_autocomplete_models_loaded=0
_load_models_from_json 2>/dev/null

# Build options array like model_command does
local sorted_keys
sorted_keys=()
for key in ${(k)_autocomplete_modellist}; do
    sorted_keys+=("$key")
done
sorted_keys=(${(o)sorted_keys[@]})

local model_options=()
for key in "${sorted_keys[@]}"; do
    model_options+=("$key")
done

echo "Total options: ${#model_options[@]}"
echo "First 5 options:"
for i in {1..5}; do
    echo "  model_options[$i] = '${model_options[$i]}'"
done

# Check if haiku is really first
if [[ "${model_options[1]}" =~ "haiku" ]]; then
    echo -e "\nHaiku is at position 1!"
    echo "Value in modellist: '${_autocomplete_modellist[${model_options[1]}]}'"
else
    echo -e "\nHaiku is NOT at position 1"
    # Find where it is
    for i in {1..10}; do
        if [[ "${model_options[$i]}" =~ "haiku" ]]; then
            echo "Found haiku at position $i: '${model_options[$i]}'"
        fi
    done
fi