#!/bin/zsh

# Test what happens with return code handling

test_function() {
    return 1
}

test_function
rc=$?
echo "Return code: $rc"

# Test array access with rc=1
arr=("zero" "one" "two")
echo "arr[1] = '${arr[1]}'"
echo "arr[$rc] = '${arr[$rc]}'"

# The issue might be that menu_selector returns 1 for the first item
# but model_command checks if return code is 1 to detect cancellation

echo -e "\nChecking model_command logic:"
echo "Line 1301-1302 checks if selected_option -eq 255 for cancellation"
echo "So return code 1 should be valid for first item"