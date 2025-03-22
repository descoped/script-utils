#!/bin/bash

# Bash script to wrap the Python file appender script

MIN_PYTHON_VERSION="3.7"  # Set your minimum required Python version here

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect if UV package manager is being used
is_using_uv() {
    if [ -f "pyproject.toml" ]; then
        grep -q "\[project\]" pyproject.toml
        return $?
    fi
    return 1
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
REQUIRED_PKG="click pyperclip tqdm pyyaml"

# Check if we should use UV or regular pip
if is_using_uv; then
    echo "UV package manager detected (pyproject.toml with [project] section found)"
    INSTALL_CMD="uv pip install"

    # Check if UV is installed
    if ! command_exists uv; then
        echo "Error: UV package manager is not installed. Please install UV and try again."
        exit 1
    fi
else
    INSTALL_CMD="pip3 install"
fi

# Check if each required package is installed, if not, install it
for pkg in $REQUIRED_PKG; do
    if ! python3 -c "import ${pkg/pyyaml/yaml}" &> /dev/null; then
        echo "Package $pkg not found. Installing using $INSTALL_CMD..."
        $INSTALL_CMD $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing $pkg. Please check your Python and package manager setup."
            if [ "$pkg" = "pyyaml" ]; then
                echo "Warning: YAML configuration support will be limited."
            else
                exit 1
            fi
        fi
    fi
done

# Get the directory of the bash script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the Python scripts
PYTHON_SCRIPT="${SCRIPT_DIR}/append-files.py"
EXTRACT_SCRIPT="${SCRIPT_DIR}/extract-code-signatures.py"

# Check if the Python scripts exist
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

if [ ! -f "$EXTRACT_SCRIPT" ]; then
    echo "Warning: extract-code-signatures.py not found at $EXTRACT_SCRIPT"
    echo "Transform functionality will be limited"
fi

# Run the Python script with all arguments
python3 "$PYTHON_SCRIPT" "$@"