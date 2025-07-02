#!/bin/zsh

# Simple test of menu_selector return value

test_menu() {
    local selected=1
    # Simulate selecting the first item
    return $selected
}

echo "Testing menu return value..."
test_menu
result=$?
echo "Menu returned: $result"

# Test array access
arr=("first" "second" "third")
echo "arr[$result] = '${arr[$result]}'"

# Check what position 1 means
echo -e "\nArray contents:"
echo "arr[0] = '${arr[0]}'"
echo "arr[1] = '${arr[1]}'"
echo "arr[2] = '${arr[2]}'"
echo "arr[3] = '${arr[3]}'"