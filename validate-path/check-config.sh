#!/usr/bin/env bash

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to detect if output is being piped
is_piped() {
    [ -t 1 ] && return 1 || return 0
}

# Function to echo with color, accounting for piped output
echo_color() {
    local color=$1
    local message=$2
    if is_piped; then
        echo "$message"
    else
        echo -e "${color}${message}${NC}"
    fi
}

# Global variables
VERBOSE=false
PROCESSED_FILES=()
COMPUTED_PATH=""

# Function to print verbose messages
verbose() {
    if [[ "$VERBOSE" = true ]]; then
        echo_color "$BLUE" "[VERBOSE] $1"
    fi
}

# Function to process a file
process_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo_color "$YELLOW" "Warning: File $file does not exist. Skipping."
        return
    fi

    # Check for circular references
    if [[ " ${PROCESSED_FILES[@]} " =~ " ${file} " ]]; then
        echo_color "$YELLOW" "Warning: Circular reference detected for $file. Skipping to prevent infinite loop."
        return
    fi

    PROCESSED_FILES+=("$file")

    local line_number=1

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check for source or . commands
        if [[ $line =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+) ]]; then
            sourced_file="${BASH_REMATCH[2]}"
            sourced_file="${sourced_file//\"/}"  # Remove quotes if present
            sourced_file="${sourced_file//\$/}"  # Remove $ if present (for cases like $HOME/.some_file)
            # Expand ~ to $HOME
            sourced_file="${sourced_file/#\~/$HOME}"
            # Resolve relative paths
            sourced_file=$(readlink -f "$sourced_file" 2>/dev/null || echo "$sourced_file")
            echo_color "$GREEN" "Sourced file: $sourced_file (from $file:$line_number)"
            # Recursively process the sourced file
            process_file "$sourced_file"
        fi

        # Check for PATH modifications
        if [[ $line =~ (PATH=|export[[:space:]]+PATH=|PATH=.*:\$PATH|PATH=.*:\${PATH}|PATH=\$PATH:.*|PATH=\${PATH}:.*) ]]; then
            echo_color "$GREEN" "Config file: $file, Line: $line_number, Content: $line"
            # Update COMPUTED_PATH (this is a simplification and might not catch all cases)
            if [[ $line =~ PATH=(.+) ]]; then
                COMPUTED_PATH="${BASH_REMATCH[1]}"
                COMPUTED_PATH="${COMPUTED_PATH//\$PATH/$COMPUTED_PATH}"
            fi
        fi

        ((line_number++))
    done < "$file"
}

# Function to check for duplicate PATH entries
check_duplicates() {
    local IFS=':'
    declare -A path_entries
    local duplicates=false

    for entry in $COMPUTED_PATH; do
        if [[ -n "${path_entries[$entry]}" ]]; then
            echo_color "$YELLOW" "Duplicate PATH entry found: $entry"
            duplicates=true
        else
            path_entries[$entry]=1
        fi
    done

    if [[ "$duplicates" = false ]]; then
        echo_color "$GREEN" "No duplicate PATH entries found."
    fi
}

# Main script
main() {
    local shell_type=$1
    local config_files=()

    case $shell_type in
        zsh)
            config_files=("$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin")
            ;;
        bash)
            config_files=("$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile")
            ;;
        *)
            echo_color "$RED" "Usage: $0 [-v] [zsh|bash]"
            exit 1
            ;;
    esac

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo_color "$GREEN" "Processing $file..."
            process_file "$file"
            echo
        else
            verbose "Info: $file does not exist. Skipping."
        fi
    done

    echo_color "$GREEN" "Computed PATH:"
    echo "$COMPUTED_PATH"
    echo

    check_duplicates
}

# Parse command line options
while getopts ":v" opt; do
    case ${opt} in
        v )
            VERBOSE=true
            ;;
        \? )
            echo_color "$RED" "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Run the script
if [[ $# -eq 0 ]]; then
    echo_color "$RED" "Error: No shell type specified."
    echo_color "$RED" "Usage: $0 [-v] [zsh|bash]"
    exit 1
fi

main "$1"