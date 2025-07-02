#!/bin/zsh

echo "Test 1: Source and check array"
source /Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh 2>/dev/null
echo "After sourcing: ${#_autocomplete_modellist[@]} models"

echo -e "\nTest 2: Run autocomplete as a command"
/Users/sambutler/bin/autocomplete-sh-samuelbutler/autocomplete.zsh model anthropic claude-3-5-haiku-20241022 2>&1 | grep -E "(ERROR:|Debug:)" | head -10