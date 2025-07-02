#!/bin/zsh

echo "Testing zsh array indexing..."

# Test with different array creation methods
arr1=("zero" "one" "two" "three")
echo "arr1 created with =()"
echo "  arr1[0] = '${arr1[0]}'"
echo "  arr1[1] = '${arr1[1]}'"
echo "  arr1[2] = '${arr1[2]}'"

# Check if KSH_ARRAYS is set
if [[ -o KSH_ARRAYS ]]; then
    echo "KSH_ARRAYS is ON (0-based indexing)"
else
    echo "KSH_ARRAYS is OFF (1-based indexing)"
fi

# Check the actual behavior
echo -e "\nTesting which element is first:"
first_element="${arr1[1]}"
if [[ "$first_element" == "zero" ]]; then
    echo "Arrays are 0-indexed (first element at index 1 is 'zero')"
elif [[ "$first_element" == "one" ]]; then
    echo "Arrays are 1-indexed (first element at index 1 is 'one')"
fi