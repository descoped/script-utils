#!/bin/bash

# Bash script to wrap the Python file combiner script

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Python is installed
if ! command_exists python3; then
    echo "Error: Python 3 is not installed. Please install Python 3 and try again."
    exit 1
fi

# Check if pip is installed
if ! command_exists pip3; then
    echo "Error: pip3 is not installed. Please install pip3 and try again."
    exit 1
fi

# Check if Click is installed, if not, install it
if ! python3 -c "import click" &> /dev/null; then
    echo "Click library not found. Installing..."
    pip3 install click
fi

# Get the directory of the bash script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the Python script
PYTHON_SCRIPT="${SCRIPT_DIR}/combine_files.py"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

# Run the Python script with all arguments passed to this bash script
python3 "$PYTHON_SCRIPT" "$@"
