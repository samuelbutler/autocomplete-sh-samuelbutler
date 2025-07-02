#!/bin/zsh

# Test zsh array indexing

# Use a different variable name
test_opts=("first" "second" "third")

echo "Array contents:"
for i in {1..3}; do
    echo "  test_opts[$i] = '${test_opts[$i]}'"
done

echo -e "\nTesting with selected_option=2:"
selected_option=2
echo "test_opts[selected_option] = '${test_opts[selected_option]}'"