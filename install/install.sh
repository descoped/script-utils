#!/bin/bash

set -e

# ANSI color codes for log levels
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[1;31m"
RESET="\033[0m"

# Logging function with color coding based on log level
log_message() {
    local log_level="$1"
    local message="$2"
    case "$log_level" in
        INFO)
            printf "${GREEN}[INFO]${RESET} %s\n" "$message"
            ;;
        WARNING)
            printf "${YELLOW}[WARNING]${RESET} %s\n" "$message"
            ;;
        DEBUG)
            printf "${BLUE}[DEBUG]${RESET} %s\n" "$message"
            ;;
        ERROR)
            printf "${RED}[ERROR]${RESET} %s\n" "$message"
            ;;
        *)
            printf "[LOG] %s\n" "$message"
            ;;
    esac
}

# Function to download and install file
download_and_install_file() {
    local file="$1"
    local target="$2"
    local base_url="$3"

    local file_url="$base_url/$file"
    mkdir -p "$(dirname "$target")"

    log_message DEBUG "Downloading $file from $file_url"
    curl -sSL "$file_url" -o "$target"

    if [ $? -ne 0 ]; then
        log_message ERROR "Failed to download $file_url"
        exit 1
    fi

    log_message INFO "Installed: $target"
}

# Function to prompt for a custom installation directory
prompt_for_install_dir() {
    local default_install_dir="$HOME/bin"
    local dir
    read -p "Enter installation directory [$default_install_dir]: " dir </dev/tty
    echo "${dir:-$default_install_dir}"
}

# Function to display the installation plan
display_installation_plan() {
    local install_dir="$1"
    local project_name="$2"
    local config_file="$3"
    local base_url="https://raw.githubusercontent.com/descoped/script-utils/master/$project_name"

    log_message INFO "Installation Plan:"
    printf "%s\n" "------------------"
    log_message INFO "Installing to: $install_dir"
    printf "\n"

    local files_found=false
    local lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$config_file"

    local total_lines=${#lines[@]}
    local i=0

    while [ $i -lt $total_lines ]; do
        line="${lines[$i]}"
        if [[ $line == "- file:"* ]]; then
            files_found=true
            local file=$(echo "$line" | awk '{print $3}')
            local destination=""
            local executable=false

            ((i++))
            while [ $i -lt $total_lines ]; do
                next_line="${lines[$i]}"
                if [[ $next_line == "- file:"* ]]; then
                    ((i--))
                    break
                fi
                if [[ $next_line == *"executable: true"* ]]; then
                    executable=true
                fi
                if [[ $next_line == *"destination:"* ]]; then
                    destination=$(echo "$next_line" | awk '{print $2}')
                fi
                ((i++))
            done

            local target
            if [ -n "$destination" ]; then
                target="$install_dir/$project_name/$destination/${file##*/}"
            elif [[ "$file" == */* ]]; then
                target="$install_dir/$project_name/$file"
            else
                target="$install_dir/$file"
            fi

            log_message INFO "  $file -> $target"
            if [ "$executable" = true ]; then
                log_message INFO "    (marked as executable)"
            fi
        fi
        ((i++))
    done

    if [ "$files_found" = false ]; then
        log_message ERROR "No files found in configuration."
        return 1
    fi

    printf "\n"
    return 0
}

# Function to install files based on configuration
install_files() {
    local install_dir="$1"
    local project_name="$2"
    local config_file="$3"
    local base_url="https://raw.githubusercontent.com/descoped/script-utils/master/$project_name"

    log_message INFO "Installing files..."

    local files_installed=false
    local lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$config_file"

    local total_lines=${#lines[@]}
    local i=0

    while [ $i -lt $total_lines ]; do
        line="${lines[$i]}"
        if [[ $line == "- file:"* ]]; then
            local file=$(echo "$line" | awk '{print $3}')
            local destination=""
            local executable=false

            ((i++))
            while [ $i -lt $total_lines ]; do
                next_line="${lines[$i]}"
                if [[ $next_line == "- file:"* ]]; then
                    ((i--))
                    break
                fi
                if [[ $next_line == *"executable: true"* ]]; then
                    executable=true
                fi
                if [[ $next_line == *"destination:"* ]]; then
                    destination=$(echo "$next_line" | awk '{print $2}')
                fi
                ((i++))
            done

            local target
            if [ -n "$destination" ]; then
                target="$install_dir/$project_name/$destination/${file##*/}"
            elif [[ "$file" == */* ]]; then
                target="$install_dir/$project_name/$file"
            else
                target="$install_dir/$file"
            fi

            # Download and install the file
            download_and_install_file "$file" "$target" "$base_url"

            # Set executable permissions if required
            if [ "$executable" = true ]; then
                chmod +x "$target"
                log_message INFO "  (marked as executable)"
            fi

            files_installed=true
        fi
        ((i++))
    done

    if [ "$files_installed" = false ]; then
        log_message ERROR "No files were installed."
        return 1
    fi

    return 0
}

# Main script
main() {
    local project_name="$1"
    local config_url
    local default_install_dir="$HOME/bin"

    if [ -z "$project_name" ]; then
        log_message ERROR "Project name not provided."
        echo "Usage: $0 <project_name>"
        exit 1
    fi

    config_url="https://raw.githubusercontent.com/descoped/script-utils/master/$project_name/install.yml"

    # Download configuration file
    local config_file
    config_file=$(mktemp)
    log_message INFO "Downloading configuration from $config_url"
    curl -sSL "$config_url" -o "$config_file"

    if [ ! -s "$config_file" ]; then
        log_message ERROR "The configuration file could not be downloaded or is empty."
        rm -f "$config_file"
        exit 1
    fi

    log_message DEBUG "Configuration file downloaded successfully."

    # Prompt for custom installation directory
    local install_dir
    install_dir=$(prompt_for_install_dir)
    log_message DEBUG "Install directory set to $install_dir"

    # Display installation plan
    if ! display_installation_plan "$install_dir" "$project_name" "$config_file"; then
        rm -f "$config_file"
        exit 1
    fi

    # Prompt for confirmation before proceeding
    local confirm
    read -p "Proceed with installation? [Y/n] " confirm </dev/tty
    confirm=${confirm:-Y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_message WARNING "Installation cancelled."
        rm -f "$config_file"
        exit 0
    fi

    # Install the files
    if ! install_files "$install_dir" "$project_name" "$config_file"; then
        log_message ERROR "Installation failed."
        rm -f "$config_file"
        exit 1
    fi

    # Clean up
    rm -f "$config_file"
    log_message INFO "Installation completed."
}

main "$@"
