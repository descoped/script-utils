#!/bin/bash

# Bash script to wrap the Python file appender script

MIN_PYTHON_VERSION="3.7"  # Set your minimum required Python version here

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Python 3 is installed
if ! command_exists python3; then
    echo "Error: Python 3 is not installed. Please install Python 3 and try again."
    exit 1
fi

# Get the installed Python version
PYTHON_VERSION=$(python3 --version | awk '{print $2}')

# Compare Python versions
version_compare() {
    printf "%s\n%s\n" "$1" "$2" | sort -V | head -n 1
}

# Check if the Python version is at least the minimum required version
if [[ "$(version_compare "$PYTHON_VERSION" "$MIN_PYTHON_VERSION")" != "$MIN_PYTHON_VERSION" ]]; then
    echo "Error: Python version $PYTHON_VERSION is lower than the required $MIN_PYTHON_VERSION. Please upgrade Python."
    exit 1
fi

# Check if pip is installed
if ! command_exists pip3; then
    echo "Error: pip3 is not installed. Please install pip3 and try again."
    exit 1
fi

# Required Python packages
REQUIRED_PKG="click pyperclip tqdm mimetypes"

# Check if each required package is installed, if not, install it
for pkg in $REQUIRED_PKG; do
    if ! python3 -c "import $pkg" &> /dev/null; then
        echo "Package $pkg not found. Installing..."
        pip3 install $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing $pkg. Please check your Python and pip setup."
            exit 1
        fi
    fi
done

# Get the directory of the bash script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the Python script
PYTHON_SCRIPT="${SCRIPT_DIR}/append-files.py"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

# Run the Python script with all arguments passed to this bash script
python3 "$PYTHON_SCRIPT" "$@"
