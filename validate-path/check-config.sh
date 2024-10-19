#!/usr/bin/env bash

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
VERBOSE=false
PROCESSED_FILES=()
COMPUTED_PATH=""

# Function to print verbose messages
verbose() {
    if [[ "$VERBOSE" = true ]]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}"
    fi
}

# Function to process a file
process_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}Warning: File $file does not exist. Skipping.${NC}"
        return
    fi

    # Check for circular references
    if [[ " ${PROCESSED_FILES[@]} " =~ " ${file} " ]]; then
        echo -e "${YELLOW}Warning: Circular reference detected for $file. Skipping to prevent infinite loop.${NC}"
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
            echo -e "${GREEN}Sourced file: $sourced_file (from $file:$line_number)${NC}"
            # Recursively process the sourced file
            process_file "$sourced_file"
        fi

        # Check for PATH modifications
        if [[ $line =~ (PATH=|export[[:space:]]+PATH=|PATH=.*:\$PATH|PATH=.*:\${PATH}|PATH=\$PATH:.*|PATH=\${PATH}:.*) ]]; then
            echo -e "${GREEN}Config file: $file, Line: $line_number, Content: $line${NC}"
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
    local -A path_entries
    local duplicates=false

    for entry in $COMPUTED_PATH; do
        if [[ -n "${path_entries[$entry]}" ]]; then
            echo -e "${YELLOW}Duplicate PATH entry found: $entry${NC}"
            duplicates=true
        else
            path_entries[$entry]=1
        fi
    done

    if [[ "$duplicates" = false ]]; then
        echo -e "${GREEN}No duplicate PATH entries found.${NC}"
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
            echo -e "${RED}Usage: $0 [-v] [zsh|bash]${NC}"
            exit 1
            ;;
    esac

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "${GREEN}Processing $file...${NC}"
            process_file "$file"
            echo
        else
            verbose "Info: $file does not exist. Skipping."
        fi
    done

    echo -e "${GREEN}Computed PATH:${NC}"
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
            echo -e "${RED}Invalid Option: -$OPTARG${NC}" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Run the script
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No shell type specified.${NC}"
    echo -e "${RED}Usage: $0 [-v] [zsh|bash]${NC}"
    exit 1
fi

main "$1"
