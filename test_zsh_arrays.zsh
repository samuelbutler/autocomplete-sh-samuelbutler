#!/bin/zsh

# Test zsh array indexing behavior

echo "=== Testing zsh array indexing ==="
echo

# Create a test array
test_array=("first" "second" "third" "fourth")

echo "Array contents:"
for ((i=1; i<=${#test_array[@]}; i++)); do
    echo "  Index $i: '${test_array[i]}'"
done

echo
echo "Testing return value usage:"

# Function that returns a value
test_function() {
    local selected=2
    return $selected
}

# Call function and use return value
test_function
result=$?
echo "Function returned: $result"
echo "Array element at returned index: '${test_array[$result]}'"

echo
echo "Testing menu_selector pattern:"

# Simulate what menu_selector does
simulate_menu() {
    local options=("$@")
    local selected=2
    
    echo "Options passed to function:"
    for ((i=1; i<=${#options[@]}; i++)); do
        echo "  Index $i: '${options[i]}'"
    done
    
    return $selected
}

# Test with sample options
sample_options=("option1" "option2" "option3")
simulate_menu "${sample_options[@]}"
selected_index=$?
echo
echo "Return value: $selected_index"
echo "Selected option: '${sample_options[$selected_index]}'"