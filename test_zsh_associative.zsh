#!/bin/zsh

# Test zsh associative array behavior

typeset -A test_array

# Create a key with a tab
key=$(printf "anthropic:\tclaude-3-5-haiku")
value="test value"

# Store it
test_array["$key"]="$value"

echo "Stored key: '$key'"
echo "Stored value: '$value'"

echo -e "\nIterating over keys:"
for k in ${(k)test_array}; do
    echo "  Key from iteration: '$k'"
    echo "  Value: '${test_array[$k]}'"
done

echo -e "\nDirect lookup:"
lookup_key=$(printf "anthropic:\tclaude-3-5-haiku")
echo "Lookup key: '$lookup_key'"
echo "Direct value: '${test_array[$lookup_key]}'"

echo -e "\nUsing quotes in iteration:"
for k in "${(k)test_array[@]}"; do
    echo "  Key with quotes: '$k'"
    echo "  Value: '${test_array[$k]}'"
done