#!/bin/bash

# Wrapper script for secrets-sanitizer.py
# Handles clipboard operations on macOS

# Path to the Python script (same directory as this script)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PYTHON_SCRIPT="$SCRIPT_DIR/secrets-sanitizer.py"

# Display help information
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -i, --input FILE       Read from FILE instead of clipboard"
    echo "  -o, --output FILE      Write to FILE instead of clipboard"
    echo "  -c, --clipboard        Read from clipboard (default if no input file)"
    echo "  -r, --replace          Replace clipboard content (default if no output file)"
    echo "  -v, --verbose          Show more detailed information"
    echo "  -h, --help             Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0                        # Read from clipboard, write back to clipboard"
    echo "  $0 -i debug.log           # Read from debug.log, write to clipboard"
    echo "  $0 -o sanitized.txt       # Read from clipboard, write to sanitized.txt"
    echo "  $0 -i input.txt -o output.txt  # Read from input.txt, write to output.txt"
    exit 0
}

# Default options
INPUT_FILE=""
OUTPUT_FILE=""
READ_CLIPBOARD=false
WRITE_CLIPBOARD=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--clipboard)
            READ_CLIPBOARD=true
            shift
            ;;
        -r|--replace)
            WRITE_CLIPBOARD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Set defaults if no options provided
if [[ -z "$INPUT_FILE" && "$READ_CLIPBOARD" = false ]]; then
    READ_CLIPBOARD=true
fi

if [[ -z "$OUTPUT_FILE" && "$WRITE_CLIPBOARD" = false ]]; then
    WRITE_CLIPBOARD=true
fi

# Create a temporary file for processing if needed
TEMP_FILE=""
if [[ "$READ_CLIPBOARD" = true || "$WRITE_CLIPBOARD" = true ]]; then
    TEMP_FILE=$(mktemp)
    trap 'rm -f "$TEMP_FILE" 2>/dev/null' EXIT
fi

# Prepare Python command with arguments
PYTHON_ARGS=()
if [[ "$VERBOSE" = true ]]; then
    PYTHON_ARGS+=("-v")
fi

# Get input content
if [[ -n "$INPUT_FILE" ]]; then
    PYTHON_ARGS+=("-i" "$INPUT_FILE")
elif [[ "$READ_CLIPBOARD" = true ]]; then
    # Read from clipboard using pbpaste (macOS)
    pbpaste > "$TEMP_FILE"
    PYTHON_ARGS+=("-i" "$TEMP_FILE")
    echo "Reading from clipboard"
fi

# Set output location
if [[ -n "$OUTPUT_FILE" ]]; then
    PYTHON_ARGS+=("-o" "$OUTPUT_FILE")
elif [[ "$WRITE_CLIPBOARD" = true ]]; then
    PYTHON_ARGS+=("-o" "$TEMP_FILE")
fi

# Run the Python script
python3 "$PYTHON_SCRIPT" "${PYTHON_ARGS[@]}"

# Handle clipboard output if needed
if [[ "$WRITE_CLIPBOARD" = true ]]; then
    cat "$TEMP_FILE" | pbcopy
    echo "Sanitized content copied to clipboard"
fi

exit 0