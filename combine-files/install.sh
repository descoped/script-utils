#!/bin/sh
set -e

REPO_URL="https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/combine-files"

download_file() {
    local filename=$1
    local destination=$2
    local url="$REPO_URL/$filename"
    curl -sSL -o "$destination" "$url" || { echo "Failed to download $filename"; exit 1; }
}

download_folder() {
    local foldername=$1
    local destination=$2
    local url="$REPO_URL/$foldername"
    local file_list=$(curl -sSL "$url" | grep '<a href' | sed -n 's/.*href="\([^"]*\).*/\1/p' | grep -v '^\.\.' | grep -v '^/$')
    for file in $file_list; do
        download_file "$foldername$file" "$destination/$file"
    done
}

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

# Download and parse the configuration file
config_file="install_config.yaml"
download_file "$config_file" "/tmp/$config_file"
config="/tmp/$config_file"

# Set default installation directory
default_dir="${INSTALL_DIR:-$HOME/bin}"

# Prompt user for installation directory
printf "Enter installation directory [%s]: " "$default_dir"
read -r custom_dir < /dev/tty
install_dir=${custom_dir:-$default_dir}

# Confirm installation
printf "Install scripts in %s? [Y/n] " "$install_dir"
read -r answer < /dev/tty
case "$answer" in
    [nN]*)
        echo "Installation cancelled."
        exit 0
        ;;
esac

# Create the main installation directory
mkdir -p "$install_dir/combine-files"

# Process each file in the configuration
while IFS= read -r line; do
    case "$line" in
        "- file:"*)
            file=$(echo "$line" | cut -d' ' -f3)
            executable=false
            destination="$install_dir"
            ;;
        "  executable:"*)
            executable=$(echo "$line" | cut -d' ' -f4)
            ;;
        "  destination:"*)
            subdir=$(echo "$line" | cut -d' ' -f4)
            destination="$install_dir/$subdir"
            mkdir -p "$destination"
            ;;
        *)
            # If we've reached a blank line, process the previous file or folder
            if [ -n "$file" ]; then
                if echo "$file" | grep -q '\*$'; then
                    # It's a folder
                    foldername=$(echo "$file" | sed 's/\*$//')
                    download_folder "$foldername" "$destination"
                    echo "Installed contents of $foldername to $destination"
                else
                    # It's a file
                    download_file "$file" "$destination/$file"
                    if [ "$executable" = "true" ]; then
                        chmod +x "$destination/$file"
                    fi
                    echo "Installed $file to $destination/$file"
                fi
                file=""
            fi
            ;;
    esac
done < "$config"

# Process the last file or folder if there's no blank line at the end
if [ -n "$file" ]; then
    if echo "$file" | grep -q '\*$'; then
        # It's a folder
        foldername=$(echo "$file" | sed 's/\*$//')
        download_folder "$foldername" "$destination"
        echo "Installed contents of $foldername to $destination"
    else
        # It's a file
        download_file "$file" "$destination/$file"
        if [ "$executable" = "true" ]; then
            chmod +x "$destination/$file"
        fi
        echo "Installed $file to $destination/$file"
    fi
fi

echo "Installation complete. Scripts installed in $install_dir"

# Add installation directory to PATH if it's not already there
shell_config=$(get_shell_config)
if ! echo "$PATH" | grep -q "$install_dir"; then
    echo "Adding $install_dir to PATH in $shell_config"
    echo "export PATH=\$PATH:$install_dir" >> "$shell_config"
    echo "Please restart your terminal or run 'source $shell_config' to update your PATH"
fi
