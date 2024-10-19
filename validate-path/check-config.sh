#!/usr/bin/env bash

# Function to process a file
process_file() {
    local file=$1
    local line_number=1

    while IFS= read -r line; do
        # Check for source or . commands
        if [[ $line =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+) ]]; then
            sourced_file="${BASH_REMATCH[2]}"
            sourced_file="${sourced_file//\"/}"  # Remove quotes if present
            echo "Sourced file: $sourced_file (from $file:$line_number)"
            # Recursively process the sourced file
            process_file "$sourced_file"
        fi

        # Check for PATH modifications
        if [[ $line =~ (PATH=|export[[:space:]]+PATH=|PATH=.*:\$PATH|PATH=.*:\${PATH}|PATH=\$PATH:.*|PATH=\${PATH}:.*) ]]; then
            echo "Config file: $file, Line: $line_number, Content: $line"
        fi

        ((line_number++))
    done < "$file"
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
            echo "Usage: $0 [zsh|bash]"
            exit 1
            ;;
    esac

    for file in "${config_files[@]}"; do
        if [[ -f $file ]]; then
            echo "Processing $file..."
            process_file "$file"
            echo
        fi
    done
}

# Run the script
main "$1"
