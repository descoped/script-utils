#!/usr/bin/env bash

#
# Developed with Claude 3.5 Sonnet, OpenAI 4o and OpenAI 1o-preview
#

set -eo pipefail

# ANSI color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
PROCESSED_FILES=()
COMPUTED_PATH="$PATH"
UNDEFINED_VARIABLES=()

is_piped() {
    [[ ! -t 1 ]]
}

echo_color() {
    local level=$1
    local message=$2
    local color

    case $level in
        INFO)    color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        ERROR)   color=$RED ;;
        VERBOSE) color=$BLUE ;;
        *)       color=$NC ;;
    esac

    if is_piped; then
        echo "[$level] $message"
    else
        echo -e "${color}[$level] $message${NC}"
    fi
}

log() {
    local level=$1
    local message=$2

    if [[ "$VERBOSE" = true ]] || [[ "$level" != "VERBOSE" ]]; then
        echo_color "$level" "$message"
    fi
}

# Function to check if environment variable is set
check_variable() {
    local var_name="$1"
    if [[ -z "${!var_name}" ]]; then
        UNDEFINED_VARIABLES+=("$var_name")
        log WARNING "Environment variable '$var_name' is not set. It might be defined later in the file."
        return 1
    fi
    return 0
}

process_file() {
    local file=$1

    log VERBOSE "Attempting to process file: $file"

    if [[ ! -f "$file" ]]; then
        log WARNING "File $file does not exist. Skipping."
        return
    fi

    if [[ " ${PROCESSED_FILES[*]} " =~ " ${file} " ]]; then
        log WARNING "Circular reference detected for $file. Skipping to prevent infinite loop."
        return
    fi

    PROCESSED_FILES+=("$file")

    log INFO "Processing file: $file"

    local line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        log VERBOSE "Processing line $line_number: $line"
        if [[ $line =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+) ]]; then
            process_sourced_file "${BASH_REMATCH[2]}" "$file" "$line_number"
        elif [[ $line =~ \[\[[[:space:]]-[ef][[:space:]]+(.+)[[:space:]]\]\][[:space:]]'&&'[[:space:]](.+) ]]; then
            process_conditional_source "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$file" "$line_number"
        elif [[ $line =~ ^[[:space:]]*eval[[:space:]]+(\"?\$\(.+\)\"?) ]]; then
            local eval_command="${BASH_REMATCH[1]}"
            log INFO "Eval command detected: $eval_command (from $file:$line_number)"
            log WARNING "Eval commands are not processed for safety reasons. Please check $eval_command manually."
        elif [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?PATH[=:] ]]; then
            log INFO "PATH modification detected: $file, Line: $line_number, Content: $line"
            update_computed_path "$line"
        fi
    done < "$file"
}

resolve_path() {
    local path="$1"
    local base_dir="$2"

    # Expand tilde to $HOME
    path="${path/#\~/$HOME}"

    # Expand environment variables
    path=$(eval echo "$path" 2>/dev/null) || path="$1"

    # If any variable is undefined, log and skip
    if [[ "$path" =~ \$ ]]; then
        local var_name=$(echo "$path" | grep -oP '\$\K[^/]*')
        if ! check_variable "$var_name"; then
            log WARNING "Skipping unresolved environment variable in path: $path"
            return ""
        fi
    fi

    # If the path is not absolute, make it relative to the base directory
    if [[ "$path" != /* && -n "$base_dir" ]]; then
        path="$base_dir/$path"
    fi

    # Attempt to resolve the path
    if command -v realpath >/dev/null 2>&1; then
        path=$(realpath -e "$path" 2>/dev/null) || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        path=$(readlink -f "$path" 2>/dev/null) || echo "$path"
    fi

    echo "$path"
}


process_sourced_file() {
    local sourced_file="$1"
    local source_file="$2"
    local line_number="$3"
    local original_sourced_file="$sourced_file"
    local source_dir=$(dirname "$source_file")

    # Remove any surrounding quotes
    sourced_file="${sourced_file//\"/}"
    sourced_file="${sourced_file//\'/}"

    # Resolve the path with environment variables expanded
    sourced_file=$(resolve_path "$sourced_file" "$source_dir")

    if [[ -z "$sourced_file" ]]; then
        log WARNING "Skipping unresolved path: $original_sourced_file from $source_file:$line_number"
        return
    fi

    if [[ ! -f "$sourced_file" ]]; then
        log WARNING "Sourced file does not exist or is not accessible: $sourced_file (originally $original_sourced_file from $source_file:$line_number)"
        return
    fi

    log INFO "Resolved sourced file: $sourced_file (originally $original_sourced_file from $source_file:$line_number)"
    process_file "$sourced_file"
}


process_conditional_source() {
    local conditional_file="${1//\"/}"
    local command="$2"
    conditional_file="${conditional_file/#\~/$HOME}"
    conditional_file=$(eval echo "$conditional_file")
    conditional_file=$(readlink -f "$conditional_file" 2>/dev/null || echo "$conditional_file")

    log INFO "Conditional source detected: if $conditional_file exists, executing '$command' (from $3:$4)"

    if [[ -e "$conditional_file" ]]; then
        log INFO "Condition met: $conditional_file exists. Processing command: $command"
        if [[ $command =~ source|\. ]]; then
            local sourced_file=$(echo "$command" | sed -n "s/.*source \([^ ]*\).*/\1/p")
            sourced_file="${sourced_file//\'/}"
            process_sourced_file "$sourced_file" "$3" "$4"
        else
            log WARNING "Non-source commands in conditionals are not processed. Please check '$command' manually."
        fi
    else
        log INFO "Condition not met: $conditional_file does not exist. Skipping command: $command"
    fi
}

update_computed_path() {
    local line=$1
    if [[ $line =~ PATH[=:](.*) ]]; then
        local new_path="${BASH_REMATCH[1]}"
        new_path="${new_path//\$PATH/$COMPUTED_PATH}"
        # Safely evaluate the new_path without executing commands
        new_path=$(echo "$new_path" | envsubst)
        COMPUTED_PATH="$new_path"
        log VERBOSE "Updated COMPUTED_PATH: $COMPUTED_PATH"
    fi
}

check_duplicates() {
    local IFS=':'
    local duplicates=false
    local seen=""

    for entry in $COMPUTED_PATH; do
        if [[ $seen == *":$entry:"* ]]; then
            log WARNING "Duplicate PATH entry found: $entry"
            duplicates=true
        else
            seen=":$seen$entry:"
        fi
    done

    [[ "$duplicates" = false ]] && log INFO "No duplicate PATH entries found."
}

main() {
    log VERBOSE "Starting main function"
    local config_files=(
        "$HOME/.zlogin"
        "$HOME/.zshrc"
        "$HOME/.zprofile"
        "$HOME/.zshenv"
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
    )

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            process_file "$file"
            echo
        else
            log VERBOSE "File $file does not exist. Skipping."
        fi
    done

    if [[ ${#UNDEFINED_VARIABLES[@]} -gt 0 ]]; then
        log WARNING "The following environment variables were undefined during processing: ${UNDEFINED_VARIABLES[*]}"
    fi

    log INFO "Actual Path: $PATH"
    log WARNING "Computed Path: $COMPUTED_PATH"
    echo

    check_duplicates
    log VERBOSE "Finished main function"
}

# Parse command-line options
while getopts ":v" opt; do
    case ${opt} in
        v ) VERBOSE=true ;;
        \? ) log ERROR "Invalid Option: -$OPTARG" 1>&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

log VERBOSE "Script started"
main
log VERBOSE "Script finished"
