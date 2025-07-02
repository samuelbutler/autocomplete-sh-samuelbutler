#!/bin/zsh

source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh 2>/dev/null

# Load models
_autocomplete_models_loaded=0
_load_models_from_json 2>/dev/null

# Get all keys and sort them
sorted_keys=()
for key in ${(k)_autocomplete_modellist}; do
    sorted_keys+=("$key")
done
sorted_keys=(${(o)sorted_keys[@]})

# Find claude-3-5-haiku's position
echo "Looking for claude-3-5-haiku in sorted list..."
index=1
for key in "${sorted_keys[@]}"; do
    if [[ "$key" =~ "haiku" ]]; then
        echo "Position $index: '$key'"
    fi
    if [[ $index -le 5 ]]; then
        echo "  [$index]: $key"
    fi
    ((index++))
done

echo -e "\nTotal models: ${#sorted_keys[@]}"
echo -e "\nFirst 10 anthropic models:"
index=1
for key in "${sorted_keys[@]}"; do
    if [[ "$key" =~ "anthropic" ]] && [[ $index -le 10 ]]; then
        echo "  [$index]: $key"
        ((index++))
    fi
done