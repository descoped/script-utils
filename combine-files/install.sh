#!/bin/sh
set -e

download_file() {
    local filename=$1
    local url="https://raw.githubusercontent.com/descoped/script-utils/master/combine-files/$filename"
    curl -s -O "$url" || { echo "Failed to download $filename"; exit 1; }
}

# Set default installation directory
default_dir="$HOME/bin"
install_dir="${INSTALL_DIR:-$default_dir}"

# Create the directory if it doesn't exist
mkdir -p "$install_dir"

# Change to the installation directory
cd "$install_dir"

# Download the shell script and Python script
download_file "combine_files.sh"
download_file "combine_files.py"

# Make the shell script executable
chmod +x combine_files.sh

echo "Installation complete. Scripts installed in $install_dir"
echo "You can now use the script by running: $install_dir/combine_files.sh"

# Add installation directory to PATH if it's not already there
if [ -z "$(echo "$PATH" | grep -o "$install_dir")" ]; then
    echo "Adding $install_dir to PATH in .bashrc"
    echo "export PATH=\$PATH:$install_dir" >> "$HOME/.bashrc"
    echo "Please restart your terminal or run 'source ~/.bashrc' to update your PATH"
fi
