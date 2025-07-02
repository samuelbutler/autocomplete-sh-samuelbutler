#!/bin/zsh

# Test script to debug model picker issue

# Source the autocomplete script
source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh

# Enable debugging
export DEBUG_AUTOCOMPLETE=1

echo "=== Testing model picker for claude-3-5-haiku ==="
echo

# Test 1: Load models and show haiku entries
echo "Test 1: Loading models and checking haiku entries"
_load_models_from_json

echo
echo "Test 2: Showing all keys in modellist that contain 'haiku':"
for key in ${(k)_autocomplete_modellist}; do
    if [[ "$key" =~ "haiku" ]]; then
        echo "Key: '$key'"
        echo -n "Hex: "
        echo -n "$key" | xxd -p
        echo "Value: ${_autocomplete_modellist[$key]}"
        echo
    fi
done

echo
echo "Test 3: Direct lookup tests"
# Test different key formats
test_keys=(
    "anthropic:	claude-3-5-haiku-20241022"
    "anthropic: claude-3-5-haiku-20241022"
    $'anthropic:\tclaude-3-5-haiku-20241022'
    $(printf "anthropic:\t%s" "claude-3-5-haiku-20241022")
)

for test_key in "${test_keys[@]}"; do
    echo "Testing key: '$test_key'"
    echo -n "Hex: "
    echo -n "$test_key" | xxd -p
    value="${_autocomplete_modellist[$test_key]}"
    if [[ -n "$value" ]]; then
        echo "Found value: $value"
    else
        echo "No value found"
    fi
    echo
done

echo
echo "Test 4: Simulating menu selection"
# Get all keys sorted
sorted_keys=()
for key in ${(k)_autocomplete_modellist}; do
    sorted_keys+=("$key")
done
sorted_keys=(${(o)sorted_keys[@]})

# Find haiku position
haiku_index=0
for ((i=1; i<=${#sorted_keys[@]}; i++)); do
    if [[ "${sorted_keys[i]}" =~ "haiku" ]] && [[ "${sorted_keys[i]}" =~ "claude-3-5" ]]; then
        haiku_index=$i
        echo "Found claude-3-5-haiku at index: $i"
        echo "Key: '${sorted_keys[i]}'"
        break
    fi
done

if [[ $haiku_index -gt 0 ]]; then
    selected_key="${sorted_keys[haiku_index]}"
    selected_value="${_autocomplete_modellist[$selected_key]}"
    echo "Selected key: '$selected_key'"
    echo "Selected value: '$selected_value'"
fi