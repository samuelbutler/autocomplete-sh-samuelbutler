#!/bin/zsh
# Autocomplete.zsh - LLM Powered Zsh Completion
# MIT License - ClosedLoop Technologies, Inc.
# Sean Kruzel 2024-2025
#
# This script provides zsh completion suggestions using an LLM.
# It has been migrated from the Bash version to work with zsh.
#
# Note: Do not enable “set -euo pipefail” here because it may interfere with shell completion.

###############################################################################
#                    Initialize Native Zsh Completion                        #
###############################################################################
# Make sure that the native zsh completion system is loaded
if [[ -n $ZSH_VERSION ]]; then
    autoload -Uz compinit && compinit -u
    # Enable menu selection for completions
    zmodload zsh/complist
    zstyle ':completion:*' menu select
fi

###############################################################################
#                         Enhanced Error Handling                             #
###############################################################################

error_exit() {
    echo -e "\e[31mAutocomplete.zsh - $1\e[0m" >&2
    # In a completion context, exit is too severe. Return instead.
    return 1
}

echo_error() {
    echo -e "\e[31mAutocomplete.zsh - $1\e[0m" >&2
}

echo_green() {
    echo -e "\e[32m$1\e[0m"
}

###############################################################################
#                     Global Variables & Model Definitions                    #
###############################################################################

export ACSH_VERSION=0.5.0

typeset -A _autocomplete_modellist
typeset -a _autocomplete_model_keys  # Array to preserve order
typeset -g _autocomplete_models_loaded=0

# Load models from JSON file (lazy loading)
_load_models_from_json() {
    # Check if already loaded
    if [[ $_autocomplete_models_loaded -eq 1 ]]; then
        return 0
    fi
    
    local models_file="$HOME/.autocomplete/models.json"
    if [[ ! -f "$models_file" ]]; then
        echo_error "Models file not found: $models_file" >&2
        return 1
    fi
    
    # Clear existing models
    _autocomplete_modellist=()
    _autocomplete_model_keys=()
    
    # Read and parse the JSON file more efficiently
    local models_json
    models_json=$(cat "$models_file" 2>/dev/null)
    
    # Parse all models at once using jq
    local parsed_models
    parsed_models=$(echo "$models_json" | jq -r '.models[] | "\(.provider)|\(.model)|\(.endpoint)|\(.prompt_cost)|\(.completion_cost)"' 2>/dev/null)
    
    # Process each model
    # Ensure trace is off during array operations
    { set +x; set +v; } 2>/dev/null
    while IFS='|' read -r provider model endpoint prompt_cost completion_cost; do
        # Skip if essential fields are missing
        if [[ -z "$provider" || -z "$model" || -z "$endpoint" ]]; then
            continue
        fi
        
        # Format the key with appropriate spacing
        local key
        if [[ "$provider" == "groq" ]]; then
            key=$(printf "%s:\t\t%s" "$provider" "$model")
        else
            key=$(printf "%s:\t%s" "$provider" "$model")
        fi
        
        # Create the value JSON inline
        local value="{ \"model\": \"$model\", \"provider\": \"$provider\", \"endpoint\": \"$endpoint\", \"prompt_cost\": $prompt_cost, \"completion_cost\": $completion_cost }"
        
        # Store in the associative array
        # Use unquoted key to avoid zsh's auto-quoting behavior
        _autocomplete_modellist[$key]="$value"
        
        # Also store the key in order array
        _autocomplete_model_keys+=("$key")
    done <<< "$parsed_models"
    
    # Mark as loaded
    _autocomplete_models_loaded=1
}

# Don't load models on initialization - wait until needed

###############################################################################
#                       System Information Functions                          #
###############################################################################

_get_terminal_info() {
    local terminal_info=" * User name: \$USER=$USER
 * Current directory: \$PWD=$PWD
 * Previous directory: \$OLDPWD=$OLDPWD
 * Home directory: \$HOME=$HOME
 * Operating system: \$OSTYPE=$OSTYPE
 * Shell: \$SHELL
 * Terminal type: \$TERM
 * Hostname: \$HOSTNAME"
    echo "$terminal_info"
}

machine_signature() {
    local signature
    signature=$(echo "$(uname -a)|$$USER" | md5sum | cut -d ' ' -f 1)
    echo "$signature"
}

_system_info() {
    echo "# System Information"
    echo
    uname -a
    echo "SIGNATURE: $(machine_signature)"
    echo
    echo "ZSH_VERSION: $ZSH_VERSION"
    echo "BASH_COMPLETION_VERSINFO: ${BASH_COMPLETION_VERSINFO}"
    echo
    echo "## Terminal Information"
    _get_terminal_info
}

_completion_vars() {
    echo "BASH_COMPLETION_VERSINFO: ${BASH_COMPLETION_VERSINFO}"
    echo "BUFFER: ${BUFFER}"
    echo "CURSOR: ${CURSOR}"
    echo "words: ${words[@]}"
    echo "CURRENT: ${CURRENT}"
}

###############################################################################
#                      LLM Completion Functions                               #
###############################################################################

_get_system_message_prompt() {
    echo "You are a helpful bash_completion script. Generate relevant and concise auto-complete suggestions for the given user command in the context of the current directory, operating system, command history, and environment variables. The output must be a list of two to five possible completions or rewritten commands, each on a new line, without spanning multiple lines. Each must be a valid command or chain of commands. Do not include backticks or quotes."
}

_get_output_instructions() {
    echo "Provide a list of suggested completions or commands that could be run in the terminal. YOU MUST provide a list of two to five possible completions or rewritten commands. DO NOT wrap the commands in backticks or quotes. Each must be a valid command or chain of commands. Focus on the user's intent, recent commands, and the current environment. RETURN A JSON OBJECT WITH THE COMPLETIONS."
}

_get_command_history() {
    local HISTORY_LIMIT=${ACSH_MAX_HISTORY_COMMANDS:-20}
    history | tail -n "$HISTORY_LIMIT" | tr -d '\000-\037'
}

# Refined sanitization: replace long hex sequences, UUIDs, and API-key–like tokens.
_get_clean_command_history() {
    local recent_history
    recent_history=$(_get_command_history)
    recent_history=$(echo "$recent_history" | sed -E 's/\b[[:xdigit:]]{32,40}\b/REDACTED_HASH/g')
    recent_history=$(echo "$recent_history" | sed -E 's/\b[0-9a-fA-F-]{36}\b/REDACTED_UUID/g')
    recent_history=$(echo "$recent_history" | sed -E 's/\b[A-Za-z0-9]{16,40}\b/REDACTED_APIKEY/g')
    echo "$recent_history"
}

_get_recent_files() {
    local FILE_LIMIT=${ACSH_MAX_RECENT_FILES:-20}
    find . -maxdepth 1 -type f -exec ls -ld {} + | sort -r | head -n "$FILE_LIMIT" | tr -d '\000-\037'
}

# Rewritten _get_help_message using a heredoc to preserve formatting.
_get_help_message() {
    local COMMAND HELP_INFO
    COMMAND=$(echo "$1" | awk '{print $1}')
    HELP_INFO=""
    {
        set +e
        # Get help and clean it up
        HELP_INFO=$($COMMAND --help 2>&1 || true)
        # Remove control characters and fix common problematic patterns
        # Remove ANSI escape sequences, control characters, and ensure valid UTF-8
        # Also remove escaped quotes that docker adds around paths
        HELP_INFO=$(echo "$HELP_INFO" | \
            sed 's/\x1b\[[0-9;]*m//g' | \
            sed 's/\\"/"/g' | \
            tr -d '\000-\010\013-\037\177' | \
            iconv -f UTF-8 -t UTF-8 -c)
        set -e
    } || HELP_INFO="'$COMMAND --help' not available"
    echo "$HELP_INFO"
}

_build_prompt() {
    local user_input command_history terminal_context help_message recent_files output_instructions other_environment_variables prompt
    user_input="$*"
    command_history=$(_get_clean_command_history)
    terminal_context=$(_get_terminal_info)
    # Get help message with proper escaping
    help_message=$(_get_help_message "$user_input")
    recent_files=$(_get_recent_files)
    output_instructions=$(_get_output_instructions)
    other_environment_variables=$(env | grep '=' | grep -v 'ACSH_' | awk -F= '{print $1}' | grep -v 'PWD\|OSTYPE\|BASH\|USER\|HOME\|TERM\|OLDPWD\|HOSTNAME')
    
    prompt="User command: \`$user_input\`

# Terminal Context
## Environment variables
$terminal_context

Other defined environment variables
\`\`\`
$other_environment_variables
\`\`\`

## History
Recently run commands (some information redacted):
\`\`\`
$command_history
\`\`\`

## File system
Most recently modified files:
\`\`\`
$recent_files
\`\`\`

# Instructions
$output_instructions
"
    echo "$prompt"
}

###############################################################################
#                      Payload Building Functions                             #
###############################################################################

build_common_payload() {
    # Debug variables
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo_error "Debug: model='$model'"
        echo_error "Debug: temperature='$temperature'"
        echo_error "Debug: system_prompt length=${#system_prompt}"
        echo_error "Debug: prompt_content length=${#prompt_content}"
    fi
    
    # Create temp files for the content
    local tmp_dir="/tmp/autocomplete_$$"
    mkdir -p "$tmp_dir"
    
    # Write content to temp files
    printf '%s' "$system_prompt" > "$tmp_dir/system.txt"
    printf '%s' "$prompt_content" > "$tmp_dir/prompt.txt"
    
    # Debug: save to permanent location
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        cp "$tmp_dir/system.txt" "$HOME/.autocomplete/tmp/debug_system.txt"
        cp "$tmp_dir/prompt.txt" "$HOME/.autocomplete/tmp/debug_prompt.txt"
    fi
    
    # Build JSON using the temp files
    local result
    # Check if using o3/o1 models that don't support temperature
    if [[ "$model" =~ ^(o3|o1) ]]; then
        result=$(jq -n \
            --arg model "$model" \
            --rawfile system_prompt "$tmp_dir/system.txt" \
            --rawfile prompt_content "$tmp_dir/prompt.txt" \
            '{
               model: $model,
               messages: [
                 {role: "system", content: $system_prompt},
                 {role: "user", content: $prompt_content}
               ]
            }' 2>&1)
    else
        result=$(jq -n \
            --arg model "$model" \
            --arg temperature "$temperature" \
            --rawfile system_prompt "$tmp_dir/system.txt" \
            --rawfile prompt_content "$tmp_dir/prompt.txt" \
            '{
               model: $model,
               messages: [
                 {role: "system", content: $system_prompt},
                 {role: "user", content: $prompt_content}
               ],
               temperature: ($temperature | tonumber)
            }' 2>&1)
    fi
    
    # Clean up temp files
    rm -rf "$tmp_dir"
    
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        if [[ "$result" =~ "parse error" ]]; then
            echo_error "Debug: jq error: $result"
            # Save the error and the input files
            echo "$result" > "$HOME/.autocomplete/tmp/jq_error.txt"
        else
            # Save successful result
            echo "$result" > "$HOME/.autocomplete/tmp/jq_success.json"
        fi
    fi
    
    echo "$result"
}

_build_payload() {
    local user_input prompt system_message_prompt payload acsh_prompt
    local model temperature
    model="${ACSH_MODEL:-gpt-4o}"
    temperature="${ACSH_TEMPERATURE:-0.0}"

    user_input="$1"
    prompt=$(_build_prompt "$@")
    system_message_prompt=$(_get_system_message_prompt)

    acsh_prompt="# SYSTEM PROMPT
$system_message_prompt
# USER MESSAGE
$prompt"
    export ACSH_PROMPT="$acsh_prompt"

    # Clean control characters from prompts to avoid JSON parsing errors
    # Also ensure valid UTF-8 and remove any problematic characters
    prompt_content=$(echo "$prompt" | \
        sed 's/\x1b\[[0-9;]*m//g' | \
        tr -d '\000-\010\013-\037\177' | \
        iconv -f UTF-8 -t UTF-8 -c)
    system_prompt=$(echo "$system_message_prompt" | \
        sed 's/\x1b\[[0-9;]*m//g' | \
        tr -d '\000-\010\013-\037\177' | \
        iconv -f UTF-8 -t UTF-8 -c)
    
    # Debug: save raw content
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        mkdir -p "$HOME/.autocomplete/tmp"
        echo "$prompt" > "$HOME/.autocomplete/tmp/raw_prompt.txt"
        echo "$system_message_prompt" > "$HOME/.autocomplete/tmp/raw_system.txt"
    fi

    local base_payload
    # Don't suppress errors during debug
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        base_payload=$(build_common_payload)
    else
        base_payload=$(build_common_payload 2>/dev/null)
    fi

    case "${(U)ACSH_PROVIDER}" in
        "ANTHROPIC")
            if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
                echo_error "Debug: Building Anthropic payload..."
                echo "$base_payload" > "$HOME/.autocomplete/tmp/base_payload.json"
            fi
            # Save base payload to file to avoid pipe issues
            local tmp_base="/tmp/autocomplete_base_$$.json"
            echo "$base_payload" > "$tmp_base"
            
            payload=$(jq '. + {
                system: .messages[0].content,
                messages: [{role:"user", content: .messages[1].content}],
                max_tokens: 1024,
                tool_choice: {type: "tool", name: "bash_completions"},
                tools: [{
                    name: "bash_completions",
                    description: "syntactically correct command-line suggestions",
                    input_schema: {
                        type: "object",
                        properties: {
                            commands: {type: "array", items: {type: "string", description: "A suggested command"}}
                        },
                        required: ["commands"]
                    }
                }]
            }' "$tmp_base" 2>&1)
            
            rm -f "$tmp_base"
            
            if [[ -n "$DEBUG_AUTOCOMPLETE" ]] && [[ "$payload" =~ "parse error" ]]; then
                echo_error "Debug: Anthropic payload error: $payload"
            fi
            ;;
        "GROQ")
            payload=$(echo "$base_payload" | jq '. + {response_format: {type: "json_object"}}' 2>/dev/null)
            ;;
        "OLLAMA")
            payload=$(echo "$base_payload" | jq '. + {
                format: "json",
                stream: false,
                options: {temperature: (.temperature | tonumber)}
            }' 2>/dev/null)
            ;;
        *)
            # For OpenAI, check if using newer models that require max_completion_tokens
            if [[ "${ACSH_MODEL}" =~ ^(o3|o1) ]]; then
                payload=$(echo "$base_payload" | jq '. + {
                    max_completion_tokens: 5000,
                    response_format: {type: "json_object"},
                    tool_choice: {
                        type: "function",
                        function: {
                            name: "bash_completions",
                            description: "syntactically correct command-line suggestions",
                            parameters: {
                                type: "object",
                                properties: {
                                    commands: {type: "array", items: {type: "string", description: "A suggested command"}}
                                },
                                required: ["commands"]
                            }
                        }
                    },
                    tools: [{
                        type: "function",
                        function: {
                            name: "bash_completions",
                            description: "syntactically correct command-line suggestions",
                            parameters: {
                                type: "object",
                                properties: {
                                    commands: {type: "array", items: {type: "string", description: "A suggested command"}}
                                },
                                required: ["commands"]
                            }
                        }
                    }]
                }' 2>/dev/null)
            else
                payload=$(echo "$base_payload" | jq '. + {
                    max_tokens: 200,
                    response_format: {type: "json_object"},
                    tool_choice: {
                        type: "function",
                        function: {
                            name: "bash_completions",
                            description: "syntactically correct command-line suggestions",
                            parameters: {
                                type: "object",
                                properties: {
                                    commands: {type: "array", items: {type: "string", description: "A suggested command"}}
                                },
                                required: ["commands"]
                            }
                        }
                    },
                    tools: [{
                        type: "function",
                        function: {
                            name: "bash_completions",
                            description: "syntactically correct command-line suggestions",
                            parameters: {
                                type: "object",
                                properties: {
                                    commands: {type: "array", items: {type: "string", description: "A suggested command"}}
                                },
                                required: ["commands"]
                            }
                        }
                    }]
                }' 2>/dev/null)
            fi
            ;;
    esac
    echo "$payload"
}

log_request() {
    local user_input response_body user_input_hash log_file prompt_tokens completion_tokens created api_cost
    local prompt_tokens_int completion_tokens_int
    user_input="$1"
    response_body="$2"
    user_input_hash=$(echo -n "$user_input" | md5sum | cut -d ' ' -f 1)

    if [[ "${(U)ACSH_PROVIDER}" == "ANTHROPIC" ]]; then
        prompt_tokens=$(echo "$response_body" | jq -r '.usage.input_tokens')
        prompt_tokens_int=$((prompt_tokens))
        completion_tokens=$(echo "$response_body" | jq -r '.usage.output_tokens')
        completion_tokens_int=$((completion_tokens))
    else
        prompt_tokens=$(echo "$response_body" | jq -r '.usage.prompt_tokens')
        prompt_tokens_int=$((prompt_tokens))
        completion_tokens=$(echo "$response_body" | jq -r '.usage.completion_tokens')
        completion_tokens_int=$((completion_tokens))
    fi

    created=$(date +%s)
    created=$(echo "$response_body" | jq -r ".created // $created")
    api_cost=$(echo "$prompt_tokens_int * $ACSH_API_PROMPT_COST + $completion_tokens_int * $ACSH_API_COMPLETION_COST" | bc)
    log_file=${ACSH_LOG_FILE:-"$HOME/.autocomplete/autocomplete.log"}
    echo "$created,$user_input_hash,$prompt_tokens_int,$completion_tokens_int,$api_cost" >> "$log_file"
}

openai_completion() {
    local content status_code response_body default_user_input user_input api_key payload endpoint timeout attempt max_attempts
    endpoint=${ACSH_ENDPOINT:-"https://api.openai.com/v1/chat/completions"}
    # Use shorter timeout for interactive completion
    timeout=${ACSH_TIMEOUT:-5}
    default_user_input="Write two to six most likely commands given the provided information"
    user_input=${*:-$default_user_input}

    if [[ -z "$ACSH_ACTIVE_API_KEY" && ${(U)ACSH_PROVIDER} != "OLLAMA" ]]; then
        echo_error "ACSH_ACTIVE_API_KEY not set. Please set it with: export ${(U)ACSH_PROVIDER}_API_KEY=<your-api-key>"
        return
    fi
    api_key="${ACSH_ACTIVE_API_KEY:-$OPENAI_API_KEY}"
    payload=$(_build_payload "$user_input")
    
    # Check if payload is empty or contains error
    if [[ -z "$payload" ]] || [[ "$payload" =~ "parse error" ]]; then
        # Use a simple fallback payload based on provider
        if [[ "${(U)ACSH_PROVIDER}" == "ANTHROPIC" ]]; then
            payload=$(cat <<EOF
{
  "model": "${ACSH_MODEL:-claude-3-5-sonnet-20241022}",
  "system": "You are a helpful bash completion assistant. Generate command-line completions.",
  "messages": [
    {"role": "user", "content": "Provide completions for: $user_input"}
  ],
  "temperature": 0,
  "max_tokens": 200,
  "tool_choice": {"type": "tool", "name": "bash_completions"},
  "tools": [{
    "name": "bash_completions",
    "description": "Provide command-line completion suggestions",
    "input_schema": {
      "type": "object",
      "properties": {
        "commands": {
          "type": "array",
          "items": {"type": "string", "description": "A suggested command"},
          "description": "Array of 2-5 command completions"
        }
      },
      "required": ["commands"]
    }
  }]
}
EOF
)
        else
            # Check if using newer OpenAI models that require max_completion_tokens
            if [[ "${ACSH_MODEL}" =~ ^(o3|o1) ]]; then
                payload=$(cat <<EOF
{
  "model": "${ACSH_MODEL:-gpt-4o-mini}",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant that provides bash command completions. Return ONLY a JSON object with a 'commands' array containing 2-5 command completions."},
    {"role": "user", "content": "Provide completions for: $user_input"}
  ],
  "max_completion_tokens": 5000,
  "tools": [{
    "type": "function",
    "function": {
      "name": "bash_completions",
      "description": "Return command completions",
      "parameters": {
        "type": "object",
        "properties": {
          "commands": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Array of command completions"
          }
        },
        "required": ["commands"]
      }
    }
  }],
  "tool_choice": "auto"
}
EOF
)
            else
                payload=$(cat <<EOF
{
  "model": "${ACSH_MODEL:-gpt-4o-mini}",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant that provides command completions. Suggest 2-5 completions for the given command."},
    {"role": "user", "content": "Provide completions for: $user_input"}
  ],
  "temperature": 0,
  "max_tokens": 100
}
EOF
)
            fi
    fi
    fi
    
    # Always save payload for debugging API errors
    mkdir -p "$HOME/.autocomplete/tmp"
    echo "$payload" > "$HOME/.autocomplete/tmp/autocomplete_payload.json"
    
    # Debug: Save payload to file for inspection
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo_error "Debug: Payload saved to $HOME/.autocomplete/tmp/autocomplete_payload.json"
        # Validate JSON
        if ! echo "$payload" | jq . >/dev/null 2>&1; then
            echo_error "Debug: Invalid JSON generated!"
            echo "$payload" | jq . 2>&1 | head -5
        fi
    fi
    
    max_attempts=1  # Don't retry during tab completion
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if [[ "${(U)ACSH_PROVIDER}" == "ANTHROPIC" ]]; then
            response=$(curl -s -m "$timeout" -w "\n%{http_code}" "$endpoint" \
                -H "content-type: application/json" \
                -H "anthropic-version: 2023-06-01" \
                -H "x-api-key: $api_key" \
                --data "$payload")
        elif [[ "${(U)ACSH_PROVIDER}" == "OLLAMA" ]]; then
            response=$(curl -s -m "$timeout" -w "\n%{http_code}" "$endpoint" --data "$payload")
        else
            response=$(\curl -s -m "$timeout" -w "\n%{http_code}" "$endpoint" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $api_key" \
                -d "$payload")
        fi
        status_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | sed '$d')
        if [[ $status_code -eq 200 ]]; then
            break
        else
            echo_error "API call failed with status $status_code. Retrying... (Attempt $attempt of $max_attempts)"
            sleep 1
            attempt=$((attempt+1))
        fi
    done

    if [[ $status_code -ne 200 ]]; then
        # Log error for debugging
        echo "$(date): API Error $status_code for '$user_input'" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
        echo "Response: $response_body" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
        
        case $status_code in
            400) 
                echo_error "Bad Request: The API request was invalid or malformed."
                if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
                    echo_error "Response: $response_body"
                fi
                ;;
            401) echo_error "Unauthorized: The provided API key is invalid or missing." ;;
            429) echo_error "Too Many Requests: The API rate limit has been exceeded." ;;
            500) echo_error "Internal Server Error: An unexpected error occurred on the API server." ;;
            *) echo_error "Unknown Error: Unexpected status code $status_code received. Response: $response_body" ;;
        esac
        return
    fi

    # Debug: log response
    echo "$(date): Got response for '$user_input', provider: ${(U)ACSH_PROVIDER}" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
    echo "Response body length: ${#response_body}" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
    # Save full response for debugging
    echo "$response_body" > "$HOME/.autocomplete/tmp/last_response.json"
    
    if [[ "${(U)ACSH_PROVIDER}" == "ANTHROPIC" ]]; then
        # Extract tool response
        content=$(echo "$response_body" | jq -r '.content[0].input.commands' 2>/dev/null)
        echo "Extracted Anthropic content: $content" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
    elif [[ "${(U)ACSH_PROVIDER}" == "GROQ" ]]; then
        content=$(echo "$response_body" | jq -r '.choices[0].message.content' 2>/dev/null)
        content=$(echo "$content" | jq -r '.completions' 2>/dev/null)
    elif [[ "${(U)ACSH_PROVIDER}" == "OLLAMA" ]]; then
        content=$(echo "$response_body" | jq -r '.message.content' 2>/dev/null)
        content=$(echo "$content" | jq -r '.completions' 2>/dev/null)
    else
        content=$(echo "$response_body" | jq -r '.choices[0].message.tool_calls[0].function.arguments' 2>/dev/null)
        content=$(echo "$content" | jq -r '.commands' 2>/dev/null)
    fi

    local completions
    completions=$(echo "$content" | jq -r '.[]' 2>/dev/null | grep -v '^$' || echo "$content")
    
    # If jq failed, try to extract commands manually
    if [[ -z "$completions" ]] && [[ -n "$content" ]]; then
        completions="$content"
    fi
    
    echo -n "$completions"
    log_request "$user_input" "$response_body"
}

###############################################################################
#                        Completion Functions                                 #
###############################################################################

list_cache() {
    local cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"}
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        find "$cache_dir" -maxdepth 1 -type f -name "acsh-*" -exec stat -f "%m %N" {} \; | sort -n
    else
        # Linux
        find "$cache_dir" -maxdepth 1 -type f -name "acsh-*" -printf '%T+ %p\n' | sort
    fi
}

_autocompletesh() {
    local state line command current user_input completions user_input_hash
    
    # Prevent zsh from adding backslashes or modifying the buffer
    setopt localoptions noshglob noksharrays menucomplete
    
    # Check if we're already loading to prevent duplicate messages
    if [[ -n "$ACSH_LOADING" ]]; then
        return
    fi
    
    # Get the current command line state from the original buffer
    # Use LBUFFER (left of cursor) to avoid completion artifacts
    user_input="${LBUFFER}"
    command="${words[1]}"
    current="${words[CURRENT]}"
    
    # Debug logging to understand the issue
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo "CURRENT=$CURRENT, words=(${words[@]}), LBUFFER='$LBUFFER'" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
    fi
    
    # Clean up any artifacts zsh might have added
    user_input="${user_input%\\}"
    user_input="${user_input% }"
    
    # Remove any parse error messages that got into the buffer
    if [[ "$user_input" =~ "parse.*error:" ]]; then
        # Extract just the original command before the error
        user_input=$(echo "$user_input" | sed 's/parse.*error:.*//' | sed 's/[[:space:]]*$//')
    fi
    
    # Don't try default completions - go straight to LLM
    # This prevents directory listings from appearing
    if true; then
        acsh_load_config
        if [[ -z "$ACSH_ACTIVE_API_KEY" && ${(U)ACSH_PROVIDER} != "OLLAMA" ]]; then
            local provider_key="${ACSH_PROVIDER:-openai}_API_KEY"
            provider_key=$(echo "$provider_key" | tr '[:lower:]' '[:upper:]')
            echo_error "${provider_key} is not set. Please set it using: export ${provider_key}=<your-api-key> or disable autocomplete via: autocomplete disable"
            echo
            return
        fi
        
        user_input_hash=$(echo -n "$user_input" | md5sum | cut -d ' ' -f 1)
        
        # Debug user input (disabled during completion to avoid output issues)
        # if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        #     echo_error "Debug: user_input='$user_input'"
        #     echo_error "Debug: BUFFER='$BUFFER'"
        # fi
        export ACSH_INPUT="$user_input"
        export ACSH_PROMPT=
        export ACSH_RESPONSE=
        local cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"}
        local cache_size=${ACSH_CACHE_SIZE:-100}
        local cache_file="$cache_dir/acsh-$user_input_hash.txt"
        
        if [[ -d "$cache_dir" && "$cache_size" -gt 0 && -f "$cache_file" ]]; then
            completions=$(cat "$cache_file" || true)
            touch "$cache_file"
        else
            # Set loading flag
            export ACSH_LOADING=1
            
            # Show loading message on the next line
            printf '\nLoading completions...' >&2
            
            # Make API request
            completions=$(openai_completion "$user_input" 2>/dev/null || true)
            
            # Clear loading message by moving up and clearing the line
            printf '\033[1A\033[2K' >&2
            unset ACSH_LOADING
            if [[ -d "$cache_dir" && "$cache_size" -gt 0 ]]; then
                echo "$completions" > "$cache_file"
                while [[ $(list_cache | wc -l) -gt "$cache_size" ]]; do
                    oldest=$(list_cache | head -n 1 | cut -d ' ' -f 2-)
                    rm "$oldest" || true
                done
            fi
        fi
        
        export ACSH_RESPONSE=$completions
        
        # Debug: show what we got
        if [[ -n "$completions" ]]; then
            echo "$(date): Got completions for '$user_input':" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
            echo "$completions" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
            echo "---" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
        else
            echo "$(date): No completions returned for '$user_input'" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
        fi
        
        if [[ -n "$completions" ]]; then
            local num_rows
            num_rows=$(echo "$completions" | wc -l)
            local -a suggestions
            
            if [[ $num_rows -eq 1 ]]; then
                # Single completion - clear prefix to prevent duplication
                PREFIX=""
                SUFFIX=""
                compadd -Q -- "$completions"
                return
            else
                # Multiple completions
                local -a actual_commands
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        # Strip any comments or descriptions after # or multiple spaces first
                        line=$(echo "$line" | sed 's/  *#.*//' | sed 's/  \+.*//' | sed 's/[[:space:]]*$//')
                        
                        # Remove angle brackets placeholders like <formula>, <package>, etc.
                        line=$(echo "$line" | sed 's/ <[^>]*>//g')
                        
                        # Check if this is a complete command that already includes the base command
                        if [[ "$line" == "$user_input "* ]]; then
                            # This is a full command, strip the user input prefix to avoid duplication
                            line="${line#$user_input }"
                        fi
                        
                        if [[ -n "$line" ]]; then
                            actual_commands+=("$line")
                        fi
                    fi
                done <<< "$completions"
                
                # Clear the current word and offer completions that will replace the entire line
                # Filter out any error messages
                local -a filtered_commands
                for cmd in "${actual_commands[@]}"; do
                    if [[ ! "$cmd" =~ "error:" && ! "$cmd" =~ "parse.*error" && -n "$cmd" ]]; then
                        filtered_commands+=("$cmd")
                    fi
                done
                if [[ ${#filtered_commands[@]} -gt 0 ]]; then
                    # Debug: log what we're adding
                    echo "$(date): Adding completions:" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
                    for cmd in "${filtered_commands[@]}"; do
                        echo "  '$cmd'" >> "$HOME/.autocomplete/tmp/debug_completions.txt"
                    done
                    # Add completions for the current word position
                    # Let zsh handle the display properly
                    if [[ "$user_input" == *" " ]]; then
                        # User typed "brew " with space, add as new words
                        compadd -- "${filtered_commands[@]}"
                    else
                        # User typed "brew" without space, add as continuations
                        compadd -S ' ' -- "${filtered_commands[@]}"
                    fi
                else
                    # No valid completions after filtering, try showing original
                    if [[ ${#actual_commands[@]} -gt 0 ]]; then
                        PREFIX=""
                        SUFFIX=""
                        compadd -Q -- "${actual_commands[@]}"
                    else
                        # No completions at all
                        return 0
                    fi
                fi
            fi
        fi
    fi
}

###############################################################################
#                    CLI Commands & Configuration Management                  #
###############################################################################

show_help() {
    echo_green "Autocomplete.zsh - LLM Powered Zsh Completion"
    echo "Usage: autocomplete [options] command"
    echo "       autocomplete [options] install|remove|config|model|enable|disable|clear|usage|system|command|--help"
    echo
    echo "Autocomplete.zsh enhances zsh completion with LLM capabilities."
    echo "Press Tab twice for suggestions."
    echo "Commands:"
    echo "  command             Run autocomplete (simulate double Tab)"
    echo "  command --dry-run   Show prompt without executing"
    echo "  model               Change language model"
    echo "  usage               Display usage stats"
    echo "  system              Display system information"
    echo "  config              Show or set configuration values"
    echo "    config set <key> <value>  Set a config value"
    echo "    config reset             Reset config to defaults"
    echo "  install             Install autocomplete to .zshrc"
    echo "  remove              Remove installation from .zshrc"
    echo "  enable              Enable autocomplete"
    echo "  disable             Disable autocomplete"
    echo "  clear               Clear cache and log files"
    echo "  --help              Show this help message"
    echo
    echo "Submit issues at: https://github.com/closedloop-technologies/autocomplete-sh/issues"
}

is_subshell() {
    if [[ "$$" != "$BASHPID" ]]; then
        return 0
    else
        return 1
    fi
}

show_config() {
    local config_file="$HOME/.autocomplete/config" term_width small_table
    echo_green "Autocomplete.zsh - Configuration and Settings - Version $ACSH_VERSION"
    if is_subshell; then
        echo "  STATUS: Unknown. Run 'source autocomplete config' to check status."
        return
    elif check_if_enabled; then
        echo -e "  STATUS: \033[32;5mEnabled\033[0m"
    else
        echo -e "  STATUS: \033[31;5mDisabled\033[0m - Run 'source autocomplete config' to verify."
    fi
    if [ ! -f "$config_file" ]; then
        echo_error "Configuration file not found: $config_file. Run autocomplete install."
        return
    fi
    acsh_load_config
    term_width=$(tput cols)
    if [[ $term_width -gt 70 ]]; then
        term_width=70; small_table=0
    fi
    if [[ $term_width -lt 40 ]]; then
        term_width=70; small_table=1
    fi
    for config_var in ${(k)parameters:#ACSH_*}; do
        if [[ $config_var == "ACSH_INPUT" || $config_var == "ACSH_PROMPT" || $config_var == "ACSH_RESPONSE" ]]; then
            continue
        fi
        config_value="${(P)config_var}"
        if [[ ${config_var: -8} == "_API_KEY" ]]; then
            continue
        fi
        echo -en "  $config_var:\e[90m"
        if [[ $small_table -eq 1 ]]; then
            echo -e "\n  $config_value\e[0m"
        else
            printf '%s%*s' "" $((term_width - ${#config_var} - ${#config_value} - 3)) ''
            echo -e "$config_value\e[0m"
        fi
    done
    echo -e "  ===================================================================="
    for config_var in ${(k)parameters:#ACSH_*}; do
        if [[ $config_var == "ACSH_INPUT" || $config_var == "ACSH_PROMPT" || $config_var == "ACSH_RESPONSE" ]]; then
            continue
        fi
        if [[ ${config_var: -8} != "_API_KEY" ]]; then
            continue
        fi
        echo -en "  $config_var:\e[90m"
        if [[ -z ${(P)config_var} ]]; then
            config_value="UNSET"
            echo -en "\e[31m"
        else
            rest=${(P)config_var}
            config_value="${rest:0:4}...${rest[-4,-1]}"
            echo -en "\e[32m"
        fi
        if [[ $small_table -eq 1 ]]; then
            echo -e "\n  $config_value\e[0m"
        else
            printf '%s%*s' "" $((term_width - ${#config_var} - ${#config_value} - 3)) ''
            echo -e "$config_value\e[0m"
        fi
    done
}

set_config() {
    local key="$1" value="$2" config_file="$HOME/.autocomplete/config"
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Keep key in lowercase for config file
    key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')
    
    # Debug logging
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo_error "Debug set_config: key='$key', value='$value'"
    fi
    
    if [ -z "$key" ]; then
        echo_error "SyntaxError: expected 'autocomplete config set <key> <value>'"
        return
    fi
    if [ ! -f "$config_file" ]; then
        echo_error "Configuration file not found: $config_file. Run autocomplete install."
        return
    fi
    sed -i '' "s|^\($key:\).*|\1 $value|" "$config_file"
    
    # Debug: Check if the update worked
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        local updated_value=$(grep "^$key:" "$config_file" | cut -d' ' -f2-)
        echo_error "Debug set_config: Updated value in file='$updated_value'"
    fi
    
    acsh_load_config
}

config_command() {
    local command config_file="$HOME/.autocomplete/config"
    command="${*:2}"
    if [ -z "$command" ]; then
        show_config
        return
    fi
    if [ "$2" = "set" ]; then
        local key="$3" value="$4"
        echo "Setting configuration key '$key' to '$value'"
        set_config "$key" "$value"
        echo_green "Configuration updated. Run 'autocomplete config' to view changes."
        return
    fi
    if [[ "$command" == "reset" ]]; then
        echo "Resetting configuration to default values."
        rm "$config_file" || true
        build_config
        return
    fi
    echo_error "SyntaxError: expected 'autocomplete config set <key> <value>' or 'autocomplete config reset'"
}

build_config() {
    local config_file="$HOME/.autocomplete/config" default_config
    if [ ! -f "$config_file" ]; then
        echo "Creating default configuration file at ~/.autocomplete/config"
        default_config="# ~/.autocomplete/config

# OpenAI API Key
openai_api_key: \$OPENAI_API_KEY

# Anthropic API Key
anthropic_api_key: \$ANTHROPIC_API_KEY

# Groq API Key
groq_api_key: \$GROQ_API_KEY

# Custom API Key for Ollama
custom_api_key: \$LLM_API_KEY

# Model configuration
provider: openai
model: gpt-4o
temperature: 0.0
endpoint: https://api.openai.com/v1/chat/completions
api_prompt_cost: 0.000005
api_completion_cost: 0.000015

# Max history and recent files
max_history_commands: 20
max_recent_files: 20

# Cache settings
cache_dir: \$HOME/.autocomplete/cache
cache_size: 10

# Logging settings
log_file: \$HOME/.autocomplete/autocomplete.log"
        echo "$default_config" > "$config_file"
    fi
}

acsh_load_config() {
    local config_file="$HOME/.autocomplete/config" key value
    if [ -f "$config_file" ]; then
        while IFS=':' read -r key value; do
            if [[ $key =~ ^# ]] || [[ -z $key ]]; then
                continue
            fi
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g')
            # Evaluate environment variables in the value
            if [[ $value == \$* ]]; then
                value=$(eval echo "$value")
            fi
            if [[ -n $value ]]; then
                export "ACSH_$key"="$value"
            fi
        done < "$config_file"
        if [[ -z "$ACSH_OPENAI_API_KEY" && -n "$OPENAI_API_KEY" ]]; then
            export ACSH_OPENAI_API_KEY="$OPENAI_API_KEY"
        fi
        if [[ -z "$ACSH_ANTHROPIC_API_KEY" && -n "$ANTHROPIC_API_KEY" ]]; then
            export ACSH_ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
        fi
        if [[ -z "$ACSH_GROQ_API_KEY" && -n "$GROQ_API_KEY" ]]; then
            export ACSH_GROQ_API_KEY="$GROQ_API_KEY"
        fi
        if [[ -z "$ACSH_OLLAMA_API_KEY" && -n "$LLM_API_KEY" ]]; then
            export ACSH_OLLAMA_API_KEY="$LLM_API_KEY"
        fi
        # Map custom API key to OLLAMA if needed.
        if [[ -z "$ACSH_OLLAMA_API_KEY" && -n "$ACSH_CUSTOM_API_KEY" ]]; then
            export ACSH_OLLAMA_API_KEY="$ACSH_CUSTOM_API_KEY"
        fi
        case "${ACSH_PROVIDER:-openai}" in
            "openai") export ACSH_ACTIVE_API_KEY="$ACSH_OPENAI_API_KEY" ;;
            "anthropic") export ACSH_ACTIVE_API_KEY="$ACSH_ANTHROPIC_API_KEY" ;;
            "groq") export ACSH_ACTIVE_API_KEY="$ACSH_GROQ_API_KEY" ;;
            "ollama") export ACSH_ACTIVE_API_KEY="$ACSH_OLLAMA_API_KEY" ;;
            *) echo_error "Unknown provider: $ACSH_PROVIDER" ;;
        esac
    else
        echo "Configuration file not found: $config_file"
    fi
}

install_command() {
    local bashrc_file="$HOME/.zshrc" autocomplete_setup="source autocomplete enable" autocomplete_cli_setup="compdef _autocompletesh_cli autocomplete"
    if ! command -v autocomplete &>/dev/null; then
        echo_error "autocomplete.zsh not in PATH. Follow install instructions at https://github.com/closedloop-technologies/autocomplete-sh"
        return
    fi
    if [[ ! -d "$HOME/.autocomplete" ]]; then
        echo "Creating ~/.autocomplete directory"
        mkdir -p "$HOME/.autocomplete"
    fi
    local cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"}
    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir"
    fi
    build_config
    acsh_load_config
    if ! grep -qF "$autocomplete_setup" "$bashrc_file"; then
        echo -e "# Autocomplete.zsh" >> "$bashrc_file"
        echo -e "$autocomplete_setup\n" >> "$bashrc_file"
        echo "Added autocomplete.zsh setup to $bashrc_file"
    else
        echo "Autocomplete.zsh setup already exists in $bashrc_file"
    fi
    if ! grep -qF "$autocomplete_cli_setup" "$bashrc_file"; then
        echo -e "# Autocomplete.zsh CLI" >> "$bashrc_file"
        echo -e "$autocomplete_cli_setup\n" >> "$bashrc_file"
        echo "Added autocomplete CLI completion to $bashrc_file"
    fi
    echo
    echo_green "Autocomplete.zsh - Version $ACSH_VERSION installation complete."
    echo -e "Run: source $bashrc_file to enable autocomplete."
    echo -e "Then run: autocomplete model to select a language model."
}

remove_command() {
    local config_file="$HOME/.autocomplete/config" cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"} log_file=${ACSH_LOG_FILE:-"$HOME/.autocomplete/autocomplete.log"} bashrc_file="$HOME/.zshrc"
    echo_green "Removing Autocomplete.zsh installation..."
    [ -f "$config_file" ] && { rm "$config_file"; echo "Removed: $config_file"; }
    [ -d "$cache_dir" ] && { rm -rf "$cache_dir"; echo "Removed: $cache_dir"; }
    [ -f "$log_file" ] && { rm "$log_file"; echo "Removed: $log_file"; }
    if [ -d "$HOME/.autocomplete" ]; then
        if [ -z "$(ls -A "$HOME/.autocomplete")" ]; then
            rmdir "$HOME/.autocomplete"
            echo "Removed: $HOME/.autocomplete"
        else
            echo "Skipped removing $HOME/.autocomplete (not empty)"
        fi
    fi
    if [ -f "$bashrc_file" ]; then
        if grep -qF "source autocomplete enable" "$bashrc_file"; then
            sed -i '/# Autocomplete.zsh/d' "$bashrc_file"
            sed -i '/autocomplete/d' "$bashrc_file"
            echo "Removed autocomplete.zsh setup from $bashrc_file"
        fi
    fi
    local autocomplete_script
    autocomplete_script=$(command -v autocomplete)
    if [ -n "$autocomplete_script" ]; then
        echo "Autocomplete script is at: $autocomplete_script"
        # In zsh, -p is not supported; use print -n then read.
        print -n "Remove the autocomplete script? (y/n): "
        read confirm
        if [[ $confirm == "y" ]]; then
            rm "$autocomplete_script"
            echo "Removed: $autocomplete_script"
        fi
    fi
    echo "Uninstallation complete."
}

check_if_enabled() {
    # Check if _autocompletesh is registered as a completion function
    if (( ${+_comps[*]} )); then
        return 0
    else
        return 1
    fi
}

_autocompletesh_cli() {
    local state line current
    current="${words[CURRENT]}"
    
    case "${words[2]}" in
        config)
            compadd set reset
            ;;
        command)
            compadd -- --dry-run
            ;;
        *)
            if [[ $CURRENT -eq 2 ]]; then
                compadd install remove config enable disable clear usage system command model -- --help
            fi
            ;;
    esac
}

enable_command() {
    if check_if_enabled; then
        echo_green "Reloading Autocomplete.zsh..."
        disable_command
    fi
    acsh_load_config
    # Set up zsh completion for all commands
    # The -P flag makes this the default for all commands
    compdef _autocompletesh -P '*'
    
    # Configure zsh completion behavior
    zstyle ':completion:*' file-patterns ''  # Disable file completion
    zstyle ':completion:*' matcher-list ''   # Disable fuzzy matching
    zstyle ':completion:*' menu no           # Disable menu selection
    zstyle ':completion:*' insert-tab false  # Don't insert tab
}

disable_command() {
    if check_if_enabled; then
        # Remove the catch-all completion
        compdef -d '*'
        # Restore default file completion
        zstyle -d ':completion:*' file-patterns
    fi
}

command_command() {
    local args=("$@")
    local i
    for (( i = 0; i < ${#args[@]}; i++ )); do
        if [[ "${args[i]}" == "--dry-run" ]]; then
            args[i]=""
            _build_prompt "${args[@]}"
            return
        fi
    done
    openai_completion "$@" || true
    echo
}

clear_command() {
    local cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"} log_file=${ACSH_LOG_FILE:-"$HOME/.autocomplete/autocomplete.log"}
    echo "This will clear the cache and log file."
    echo -e "Cache directory: \e[31m$cache_dir\e[0m"
    echo -e "Log file: \e[31m$log_file\e[0m"
    print -n "Are you sure? (y/n): "
    read confirm
    if [[ $confirm != "y" ]]; then
        echo "Aborted."
        return
    fi
    if [ -d "$cache_dir" ]; then
        local cache_files
        cache_files=$(list_cache)
        if [[ -n "$cache_files" ]]; then
            while IFS= read -r line; do
                file=$(echo "$line" | cut -d ' ' -f 2-)
                rm "$file"
                echo "Removed: $file"
            done <<< "$cache_files"
            echo "Cleared cache in: $cache_dir"
        else
            echo "Cache is empty."
        fi
    fi
    [ -f "$log_file" ] && { rm "$log_file"; echo "Removed: $log_file"; }
}

usage_command() {
    local log_file=${ACSH_LOG_FILE:-"$HOME/.autocomplete/autocomplete.log"} cache_dir=${ACSH_CACHE_DIR:-"$HOME/.autocomplete/cache"}
    local cache_size number_of_lines api_cost avg_api_cost
    cache_size=$(list_cache | wc -l)
    echo_green "Autocomplete.zsh - Usage Information"
    echo
    echo -n "Log file: "; echo -e "\e[90m$log_file\e[0m"
    if [ ! -f "$log_file" ]; then
        number_of_lines=0
        api_cost=0
        avg_api_cost=0
    else
        number_of_lines=$(wc -l < "$log_file")
        api_cost=$(awk -F, '{sum += $5} END {print sum}' "$log_file")
        avg_api_cost=$(echo "$api_cost / $number_of_lines" | bc -l)
    fi
    echo
    echo -e "\tUsage count:\t\e[32m$number_of_lines\e[0m"
    echo -e "\tAvg Cost:\t\$$(printf "%.4f" "$avg_api_cost")"
    echo -e "\tTotal Cost:\t\e[31m\$$(printf "%.4f" "$api_cost")\e[0m"
    echo
    echo -n "Cache Size: $cache_size of ${ACSH_CACHE_SIZE:-10} in "; echo -e "\e[90m$cache_dir\e[0m"
    echo "To clear log and cache, run: autocomplete clear"
}

###############################################################################
#                      Enhanced Interactive Menu UX                           #
###############################################################################

get_key() {
    local key
    IFS= read -rsk 1 key
    if [[ $key == $'\x1b' ]]; then
        read -rsk 2 key
        if [[ $key == "[A" ]]; then echo up; fi
        if [[ $key == "[B" ]]; then echo down; fi
    elif [[ $key == "q" ]]; then
        echo q
    elif [[ $key == $'\n' || $key == $'\r' ]]; then
        echo ""
    else
        echo "$key"
    fi
}

menu_selector() {
    options=("$@")
    selected=1
    
    # Use alternate screen buffer for menu
    tput smcup  # Save screen and switch to alternate buffer
    tput clear  # Clear once at start
    tput civis  # Hide cursor
    
    # Pre-calculate total lines needed
    local total_lines=3  # Header lines
    local prev_provider=""
    for opt in "${options[@]}"; do
        local current_provider="${opt%%:*}"
        if [[ -n "$prev_provider" && "$current_provider" != "$prev_provider" ]]; then
            ((total_lines++))  # Space between providers
        fi
        ((total_lines++))
        prev_provider="$current_provider"
    done
    
    show_menu() {
        # Move cursor to home position instead of clearing entire screen
        tput cup 0 0
        
        echo
        echo "Select a Language Model (Up/Down arrows, Enter to select, 'q' to quit):"
        
        # Get current model from config
        local current_model="${ACSH_MODEL:-}"
        
        local i display_option prev_provider=""
        for (( i=1; i<=${#options[@]}; i++ )); do
            display_option="${options[i]}"
            # Extract provider name (part before colon+tab)
            local current_provider="${display_option%%:*}"
            
            # Add empty line between different providers
            if [[ -n "$prev_provider" && "$current_provider" != "$prev_provider" ]]; then
                echo -e "\e[K"  # Clear line
            fi
            prev_provider="$current_provider"
            
            # Format: replace tab with space and ensure it's on one line
            display_option="${display_option//	/: }"
            
            # Check if this is the currently active model
            local model_from_option=$(echo "${options[i]}" | sed 's/.*:\t\+//')
            local is_current_model=0
            if [[ "$model_from_option" == "$current_model" ]]; then
                is_current_model=1
            fi
            
            if (( i == selected )); then
                echo -e "\e[1;32m> ${display_option}\e[0m\e[K"
            elif [[ $is_current_model -eq 1 ]]; then
                # Show current model in green with a marker
                echo -e "  \e[32m${display_option} [current]\e[0m\e[K"
            else
                echo -e "  ${display_option}\e[K"
            fi
        done
        
        # Clear any remaining lines from previous display
        tput cd
    }
    
    # Initial display
    show_menu
    
    while true; do
        key=$(get_key)
        case $key in
            up)
                ((selected--))
                if (( selected < 1 )); then
                    selected=${#options[@]}
                fi
                show_menu
                ;;
            down)
                ((selected++))
                if (( selected > ${#options[@]} )); then
                    selected=1
                fi
                show_menu
                ;;
            q)
                tput cnorm  # Show cursor again
                tput rmcup  # Restore original screen
                echo "Selection canceled."
                return 255  # Use 255 for cancellation instead of 1
                ;;
            "")
                tput cnorm  # Show cursor again
                tput rmcup  # Restore original screen before breaking
                break
                ;;
        esac
    done
    
    return $selected
}

model_command() {
    # Disable any trace that might be on
    set +x 2>/dev/null
    
    # Clear screen and move to top to ensure clean start
    clear
    printf '\033[H'
    
    local debug_file="$HOME/.autocomplete/debug_haiku.txt"
    {
        echo "$(date): model_command started with $# args: $@"
    } >> "$debug_file"
    
    # Suppress any spurious output by redirecting stderr to null temporarily
    {
        # Load models from JSON (only when needed)
        _load_models_from_json
    } 2>/dev/null
    
    # Debug: Check if models were loaded
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo_error "Debug: Models loaded: $_autocomplete_models_loaded"
        echo_error "Debug: Number of models: ${#_autocomplete_modellist[@]}"
    fi
    
    {
        echo "$(date): Models loaded: $_autocomplete_models_loaded"
        echo "Number of models: ${#_autocomplete_modellist[@]}"
    } >> "$debug_file"
    
    # Don't clear if debugging
    if [[ -z "$DEBUG_AUTOCOMPLETE" ]]; then
        [[ $# -eq 0 ]] && clear
    fi
    local selected_model options=()
    if [[ $# -ne 3 ]]; then
        # Use the ordered keys from the JSON file
        # Suppress any debug output during array building
        { set +x; set +v; } 2>/dev/null
        for key in "${_autocomplete_model_keys[@]}"; do
            options+=("$key")
        done
        
        # Clear terminal right before showing the header
        clear
        echo -e "\e[1;32mAutocomplete.zsh - Model Configuration\e[0m"
        
        # Debug to file for haiku testing
        local debug_file="$HOME/.autocomplete/debug_haiku.txt"
        if [[ "${options[1]}" =~ "haiku" ]]; then
            {
                echo "$(date): HAIKU DEBUG - Menu start"
                echo "First option contains haiku!"
                echo "  options[1]='${options[1]}'"
                echo "  options[2]='${options[2]}'"
                echo "  options[3]='${options[3]}'"
                echo "  Total options: ${#options[@]}"
            } >> "$debug_file"
        fi
        
        menu_selector "${options[@]}"
        selected_option=$?
        if [[ $selected_option -eq 255 ]]; then
            return
        fi
        selected_model="${options[selected_option]}"
        
        # Debug to file for haiku
        if [[ "$selected_model" =~ "haiku" ]] || [[ $selected_option -eq 1 ]]; then
            {
                echo "$(date): HAIKU DEBUG - Post-select"
                echo "  selected_option=$selected_option"
                echo "  selected_model='$selected_model'"
                echo "  Looking up in modellist..."
            } >> "$debug_file"
        fi
        
        selected_value="${_autocomplete_modellist[$selected_model]}"
        
        # Debug to file for haiku
        if [[ "$selected_model" =~ "haiku" ]] || [[ $selected_option -eq 1 ]]; then
            {
                echo "$(date): HAIKU DEBUG - Lookup result"
                echo "  selected_value='$selected_value'"
                if [[ -z "$selected_value" ]]; then
                    echo "  ERROR: Lookup failed! Model list has these haiku keys:"
                    for k in ${(k)_autocomplete_modellist}; do
                        if [[ "$k" =~ "haiku" ]]; then
                            echo "    '$k'"
                        fi
                    done
                else
                    echo "  SUCCESS: Found value!"
                    echo "  Model will be set to: $(echo "$selected_value" | jq -r '.model')"
                fi
                echo "---"
            } >> "$debug_file"
        fi
    else
        provider="$2"
        model_name="$3"
        # Use printf to ensure we have a tab character
        local key
        if [[ "$provider" == "groq" ]]; then
            key=$(printf "%s:\t\t%s" "$provider" "$model_name")
        else
            key=$(printf "%s:\t%s" "$provider" "$model_name")
        fi
        selected_value="${_autocomplete_modellist[$key]}"
        if [[ -z "$selected_value" ]]; then
            echo "ERROR: Invalid provider or model name."
            echo "Debug: Looking for key: '$key'"
            echo "Debug: Key hex:"
            echo -n "$key" | xxd -p
            echo "Debug: Available keys:"
            for k in ${(k)_autocomplete_modellist}; do
                if [[ "$k" =~ "$provider" ]]; then
                    echo "  Key: '$k'"
                    if [[ "$k" =~ "haiku" ]]; then
                        echo -n "  Hex: "
                        echo -n "$k" | xxd -p
                    fi
                fi
            done
            return 1
        fi
    fi
    # Debug: Log what we're about to set
    if [[ -n "$DEBUG_AUTOCOMPLETE" ]]; then
        echo_error "Debug: selected_value='$selected_value'"
        echo_error "Debug: model='$(echo "$selected_value" | jq -r '.model')'"
    fi
    
    set_config "model" "$(echo "$selected_value" | jq -r '.model')"
    set_config "endpoint" "$(echo "$selected_value" | jq -r '.endpoint')"
    set_config "provider" "$(echo "$selected_value" | jq -r '.provider')"
    prompt_cost=$(echo "$selected_value" | jq -r '.prompt_cost' | awk '{printf "%.8f", $1}')
    completion_cost=$(echo "$selected_value" | jq -r '.completion_cost' | awk '{printf "%.8f", $1}')
    set_config "api_prompt_cost" "$prompt_cost"
    set_config "api_completion_cost" "$completion_cost"
    
    # Reload config to update environment variables
    acsh_load_config
    
    if [[ -z "$ACSH_ACTIVE_API_KEY" && ${(U)ACSH_PROVIDER} != "OLLAMA" ]]; then
        echo -e "\e[34mSet ${(U)ACSH_PROVIDER}_API_KEY\e[0m"
        echo "Stored in ~/.autocomplete/config"
        if [[ ${(U)ACSH_PROVIDER} == "OPENAI" ]]; then
            echo "Create a new one: https://platform.openai.com/settings/profile?tab=api-keys"
        elif [[ ${(U)ACSH_PROVIDER} == "ANTHROPIC" ]]; then
            echo "Create a new one: https://console.anthropic.com/settings/keys"
        elif [[ ${(U)ACSH_PROVIDER} == "GROQ" ]]; then
            echo "Create a new one: https://console.groq.com/keys"
        fi
        print -n "Enter your ${(U)ACSH_PROVIDER} API Key: "
        read -sr user_api_key_input < /dev/tty
        clear
        echo -e "\e[1;32mAutocomplete.zsh - Model Configuration\e[0m"
        if [[ -n "$user_api_key_input" ]]; then
            export ACSH_ACTIVE_API_KEY="$user_api_key_input"
            set_config "${(L)ACSH_PROVIDER}_api_key" "$user_api_key_input"
        fi
    fi
    model="${ACSH_MODEL:-ERROR}"
    temperature=$(echo "${ACSH_TEMPERATURE:-0.0}" | awk '{printf "%.3f", $1}')
    echo -e "Provider:\t\e[90m$ACSH_PROVIDER\e[0m"
    echo -e "Model:\t\t\e[90m$model\e[0m"
    echo -e "Temperature:\t\e[90m$temperature\e[0m"
    echo
    echo -e "Cost/token:\t\e[90mprompt: \$$ACSH_API_PROMPT_COST, completion: \$$ACSH_API_COMPLETION_COST\e[0m"
    echo -e "Endpoint:\t\e[90m$ACSH_ENDPOINT\e[0m"
    echo -n "API Key:"
    if [[ -z $ACSH_ACTIVE_API_KEY ]]; then
        if [[ ${(U)ACSH_PROVIDER} == "OLLAMA" ]]; then
            echo -e "\t\e[90mNot Used\e[0m"
        else
            echo -e "\t\e[31mUNSET\e[0m"
        fi
    else
        rest=${ACSH_ACTIVE_API_KEY:4}
        config_value="${ACSH_ACTIVE_API_KEY:0:4}...${rest: -4}"
        echo -e "\t\e[32m$config_value\e[0m"
    fi
    if [[ -z $ACSH_ACTIVE_API_KEY && ${(U)ACSH_PROVIDER} != "OLLAMA" ]]; then
        echo "To set the API Key, run:"
        echo -e "\t\e[31mautocomplete config set api_key <your-api-key>\e[0m"
        echo -e "\t\e[31mexport ${(U)ACSH_PROVIDER}_API_KEY=<your-api-key>\e[0m"
    fi
    if [[ ${(U)ACSH_PROVIDER} == "OLLAMA" ]]; then
        echo "To set a custom endpoint:"
        echo -e "\t\e[34mautocomplete config set endpoint <your-url>\e[0m"
        echo "Other models can be set with:"
        echo -e "\t\e[34mautocomplete config set model <model-name>\e[0m"
    fi
    echo "To change temperature:"
    echo -e "\t\e[90mautocomplete config set temperature <temperature>\e[0m"
    echo
}

###############################################################################
#                              CLI ENTRY POINT                                #
###############################################################################

# Disable trace to prevent debug output
set +x 2>/dev/null

# For model command, create a clean execution environment
if [[ "$1" == "model" ]]; then
    # Unset any trace variables
    unset XTRACE
    unset VERBOSE
    # Force trace off
    set +xv
    # Clear immediately
    clear
fi

case "$1" in
    "--help")
        show_help
        ;;
    system)
        _system_info
        ;;
    install)
        install_command
        ;;
    remove)
        remove_command "$@"
        ;;
    clear)
        clear_command
        ;;
    usage)
        usage_command
        ;;
    model)
        model_command "$@"
        ;;
    config)
        config_command "$@"
        ;;
    enable)
        enable_command
        ;;
    disable)
        disable_command
        ;;
    command)
        command_command "$@"
        ;;
    *)
        if [[ -n "$1" ]]; then
            echo_error "Unknown command $1 - run 'autocomplete --help' for usage or visit https://autocomplete.sh"
        else
            echo_green "Autocomplete.zsh - LLM Powered Zsh Completion - Version $ACSH_VERSION - https://autocomplete.sh"
        fi
        ;;
esac
