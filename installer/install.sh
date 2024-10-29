#!/bin/bash

set -e

# ANSI color codes
readonly GREEN="\033[1;32m"
readonly YELLOW="\033[1;33m"
readonly BLUE="\033[0;34m"
readonly RED="\033[1;31m"
readonly RESET="\033[0m"

# Script constants
readonly DEFAULT_INSTALL_DIR="$HOME/bin"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/descoped/script-utils/master"

# Logging function
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        INFO)    printf "${GREEN}[INFO]${RESET} %s\n" "$message" ;;
        WARN)    printf "${YELLOW}[WARNING]${RESET} %s\n" "$message" ;;
        DEBUG)   printf "${BLUE}[DEBUG]${RESET} %s\n" "$message" ;;
        ERROR)   printf "${RED}[ERROR]${RESET} %s\n" "$message" ;;
        *)       printf "[LOG] %s\n" "$message" ;;
    esac
}

# Download file with retry
download_file() {
    local url="$1"
    local output="$2"
    local attempts=3

    while [ $attempts -gt 0 ]; do
        if curl -sSL "$url" -o "$output" 2>/dev/null; then
            return 0
        fi
        attempts=$((attempts - 1))
        [ $attempts -gt 0 ] && sleep 1
    done
    return 1
}

# Get installation directory
get_install_dir() {
    local dir
    read -p "Enter installation directory [$DEFAULT_INSTALL_DIR]: " dir </dev/tty
    echo "${dir:-$DEFAULT_INSTALL_DIR}"
}

# Display installation plan from YAML
display_installation_plan() {
    local config_file="$1"
    local install_dir="$2"
    local module_name="$3"
    local plan_file="$4"
    local found_files=false

    # Clear plan file
    > "$plan_file"

    printf "\nInstallation Plan:\n"
    printf "=================\n"
    printf "Install directory: %s\n\n" "$install_dir"
    printf "Files to install:\n"

    local current_file=""
    local current_executable=false
    local current_destination=""
    local current_symlink=false

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*file:[[:space:]]*(.+)$ ]]; then
            # Process previous file if exists
            if [ -n "$current_file" ]; then
                local target
                if [ -n "$current_destination" ]; then
                    target="$install_dir/.$module_name/$current_destination/${current_file##*/}"
                else
                    target="$install_dir/${current_file##*/}"
                fi

                printf "  • Source: %s\n" "$current_file"
                printf "    Target: %s\n" "$target"
                [ "$current_executable" = true ] && printf "    Executable: yes\n"
                if [ "$current_symlink" = true ]; then
                    local symlink_name="${target%.*}"
                    printf "    Symlink: %s\n" "$symlink_name"
                fi
                printf "\n"

                echo "$current_file|$target|$current_executable|$current_symlink" >> "$plan_file"
            fi

            # Start new file
            current_file="${BASH_REMATCH[1]}"
            current_executable=false
            current_destination=""
            current_symlink=false
            found_files=true

        elif [[ "$line" =~ ^[[:space:]]*executable:[[:space:]]*true[[:space:]]*$ ]]; then
            current_executable=true
        elif [[ "$line" =~ ^[[:space:]]*create-symlink:[[:space:]]*true[[:space:]]*$ ]]; then
            current_symlink=true
        elif [[ "$line" =~ ^[[:space:]]*destination:[[:space:]]*(.+)[[:space:]]*$ ]]; then
            current_destination="${BASH_REMATCH[1]}"
        fi
    done < "$config_file"

    # Process the last file
    if [ -n "$current_file" ]; then
        local target
        if [ -n "$current_destination" ]; then
            target="$install_dir/.$module_name/$current_destination/${current_file##*/}"
        else
            target="$install_dir/${current_file##*/}"
        fi

        printf "  • Source: %s\n" "$current_file"
        printf "    Target: %s\n" "$target"
        [ "$current_executable" = true ] && printf "    Executable: yes\n"
        if [ "$current_symlink" = true ]; then
            local symlink_name="${target%.*}"
            printf "    Symlink: %s\n" "$symlink_name"
        fi
        printf "\n"

        echo "$current_file|$target|$current_executable|$current_symlink" >> "$plan_file"
    fi

    if [ "$found_files" = false ]; then
        log ERROR "No files found in configuration"
        return 1
    fi

    return 0
}

# Install files according to plan
install_files() {
    local plan_file="$1"
    local module_name="$2"
    local base_url="$GITHUB_RAW_URL/$module_name"

    while IFS='|' read -r file target executable symlink; do
        [ -z "$file" ] && continue

        # Create target directory
        mkdir -p "$(dirname "$target")"

        log INFO "Installing: $file"
        if ! download_file "$base_url/$file" "$target"; then
            log ERROR "Failed to download: $file"
            return 1
        fi

        if [ "$executable" = "true" ]; then
            chmod +x "$target"
            log INFO "Made executable: $target"
        fi

        if [ "$symlink" = "true" ]; then
            local symlink_name="${target%.*}"
            # Remove existing symlink if it exists
            [ -L "$symlink_name" ] && rm "$symlink_name"
            # Create new symlink
            ln -s "$target" "$symlink_name"
            log INFO "Created symlink: $symlink_name -> $target"
        fi

        log INFO "Installed to: $target"
    done < "$plan_file"

    return 0
}

# Main execution
main() {
    local module_name="$1"

    if [ -z "$module_name" ]; then
        log ERROR "Module name not provided"
        echo "Usage: $0 <module_name>"
        exit 1
    fi

    # Create temporary files
    local config_file plan_file
    config_file=$(mktemp)
    plan_file=$(mktemp)
    trap 'rm -f "$config_file" "$plan_file"' EXIT

    # Download configuration
    local config_url="$GITHUB_RAW_URL/$module_name/install.yml"
    log INFO "Downloading configuration from $config_url"

    if ! download_file "$config_url" "$config_file"; then
        log ERROR "Failed to download configuration"
        exit 1
    fi

    if [ ! -s "$config_file" ]; then
        log ERROR "Configuration file is empty"
        exit 1
    fi

    # Get installation directory
    local install_dir
    install_dir=$(get_install_dir)

    # Display installation plan
    if ! display_installation_plan "$config_file" "$install_dir" "$module_name" "$plan_file"; then
        exit 1
    fi

    # Confirm installation
    read -p "Proceed with installation? [Y/n] " confirm </dev/tty
    confirm=${confirm:-Y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log WARN "Installation cancelled"
        exit 0
    fi

    printf "\n"

    # Perform installation
    if install_files "$plan_file" "$module_name"; then
        log INFO "Installation completed successfully"
    else
        log ERROR "Installation failed"
        exit 1
    fi
}

main "$@"
