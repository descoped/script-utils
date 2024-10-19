#!/bin/sh

# Check if we're running in a shell that supports advanced features
if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
    USE_COLORS=true
else
    USE_COLORS=false
fi

# ANSI color codes (only if supported)
if [ "$USE_COLORS" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Global variables
VERBOSE=false
COMPUTED_PATH=""

# Function to print verbose messages
verbose() {
    if [ "$VERBOSE" = true ]; then
        printf "${BLUE}[VERBOSE] %s${NC}\n" "$1"
    fi
}

# Function to process a file
process_file() {
    file=$1
    if [ ! -f "$file" ]; then
        printf "${YELLOW}Warning: File %s does not exist. Skipping.${NC}\n" "$file"
        return
    fi

    line_number=1

    while IFS= read -r line || [ -n "$line" ]; do
        # Check for source or . commands
        case "$line" in
            *source*|*\.*)
                sourced_file=$(echo "$line" | sed -E 's/^[[:space:]]*(source|\.)[[:space:]]+//' | tr -d '"')
                sourced_file=$(eval echo "$sourced_file") # Expand variables and ~
                printf "${GREEN}Sourced file: %s (from %s:%s)${NC}\n" "$sourced_file" "$file" "$line_number"
                # Recursively process the sourced file
                process_file "$sourced_file"
                ;;
        esac

        # Check for PATH modifications
        case "$line" in
            *PATH=*|*export[[:space:]]+PATH=*)
                printf "${GREEN}Config file: %s, Line: %s, Content: %s${NC}\n" "$file" "$line_number" "$line"
                # Update COMPUTED_PATH (this is a simplification and might not catch all cases)
                COMPUTED_PATH=$(echo "$line" | sed -E 's/^.*PATH=//;s/\$PATH/'"$COMPUTED_PATH"'/')
                ;;
        esac

        line_number=$((line_number + 1))
    done < "$file"
}

# Function to check for duplicate PATH entries
check_duplicates() {
    printf "${GREEN}Checking for duplicate PATH entries:${NC}\n"
    echo "$COMPUTED_PATH" | tr ':' '\n' | sort | uniq -d
}

# Main script
main() {
    shell_type=$1

    case $shell_type in
        zsh)
            config_files="$HOME/.zshenv $HOME/.zprofile $HOME/.zshrc $HOME/.zlogin"
            ;;
        bash)
            config_files="$HOME/.bash_profile $HOME/.bashrc $HOME/.profile"
            ;;
        *)
            printf "${RED}Usage: %s [-v] [zsh|bash]${NC}\n" "$0"
            exit 1
            ;;
    esac

    for file in $config_files; do
        if [ -f "$file" ]; then
            printf "${GREEN}Processing %s...${NC}\n" "$file"
            process_file "$file"
            echo
        else
            verbose "Info: $file does not exist. Skipping."
        fi
    done

    printf "${GREEN}Computed PATH:${NC}\n"
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
            printf "${RED}Invalid Option: -%s${NC}\n" "$OPTARG" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Run the script
if [ $# -eq 0 ]; then
    printf "${RED}Error: No shell type specified.${NC}\n"
    printf "${RED}Usage: %s [-v] [zsh|bash]${NC}\n" "$0"
    exit 1
fi

main "$1"