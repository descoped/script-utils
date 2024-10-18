#!/bin/bash

# Base URL for raw content
BASE_URL="https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/combine-files"

# Function to download a file
download_file() {
    local file="$1"
    local url="${BASE_URL}/${file}"
    curl -sSL "$url" -o "$file"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download $file"
        exit 1
    fi
}

# Function to parse YAML-like config
parse_config() {
    sed 's/^- //' | sed 's/: /=/' | sed 's/^/export /'
}

# Function to get the appropriate shell config file
get_shell_config() {
    if [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        echo "$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        echo "$HOME/.bash_profile"
    else
        echo "$HOME/.profile"
    fi
}

# Function to add directory to PATH
add_to_path() {
    local dir="$1"
    local config_file=$(get_shell_config)
    if ! grep -q "export PATH=\"$dir:\$PATH\"" "$config_file"; then
        echo "export PATH=\"$dir:\$PATH\"" >> "$config_file"
        echo "Added $dir to PATH in $config_file"
    else
        echo "$dir is already in PATH"
    fi
}

# Download the config file
config_file="install-config.yml"
download_file "$config_file"

# Prompt for installation directory
read -p "Enter installation directory [default: $HOME/bin]: " install_dir
install_dir=${install_dir:-$HOME/bin}

# Show installation plan
echo "Installation Plan:"
echo "------------------"
while IFS= read -r line; do
    if [[ $line == "- file:"* ]]; then
        file=$(echo "$line" | awk '{print $3}')
        destination=$(grep -A3 "^$line$" "$config_file" | grep "destination:" | awk '{print $2}')
        executable=$(grep -A3 "^$line$" "$config_file" | grep "executable:" | awk '{print $2}')
        destination=${destination:-.}
        if [[ $destination == "." ]]; then
            echo -n "$install_dir/$file"
        else
            echo -n "$install_dir/combine_files/$destination/$(basename "$file")"
        fi
        [[ $executable == "true" ]] && echo " (executable)" || echo ""
    fi
done < "$config_file"
echo "------------------"

# Prompt for confirmation
read -p "Proceed with installation? [Y/n]: " confirm
confirm=${confirm:-Y}
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Create installation directory
mkdir -p "$install_dir"

# Process each file in the config
while IFS= read -r line; do
    if [[ $line == "- file:"* ]]; then
        # Reset variables
        unset file executable destination

        # Parse the config for this file
        eval "$(parse_config <<< "$(sed -n "/^$line$/,/^-/p" "$config_file" | sed '$d')")"

        # Set default values
        executable=${executable:-false}
        destination=${destination:-.}

        # Create destination directory
        if [[ $destination == "." ]]; then
            target_dir="$install_dir"
        else
            target_dir="$install_dir/combine_files/$destination"
        fi
        mkdir -p "$target_dir"

        # Download the file
        download_file "$file"
        mv "$file" "$target_dir/$(basename "$file")"

        # Make executable if specified
        if [ "$executable" = true ]; then
            echo "Making $file executable"
            chmod +x "$target_dir/$(basename "$file")"
        fi

        echo "Installed: $file"
    fi
done < "$config_file"

# Add installation directory to PATH
add_to_path "$install_dir"

# Clean up
rm "$config_file"

echo "Installation complete!"
echo "Please restart your terminal or run 'source $(get_shell_config)' to apply the PATH changes."
