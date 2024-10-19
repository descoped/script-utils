# Validate Path

A simple shell script to validate your terminal's PATH environment variable. This script checks each directory in your PATH to determine if it exists or if there are any empty entries.

## Features

- Verifies the existence of each directory in your PATH
- Detects and reports empty path entries (often caused by double colons '::' in the PATH)
- Easy to run as a one-liner in your terminal

## Usage

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/validate-path/validate-path.sh | sh
```

## Output

The script will output each path in your PATH variable, along with its status:

- `<path> exists`: The directory exists
- `<path> does not exist`: The directory does not exist
- `Empty (::) path exists`: An empty path entry was detected (usually due to '::' in the PATH)

## Why Use This Script?

1. **Security**: Identify any unexpected or potentially risky directories in your PATH.
2. **Troubleshooting**: Quickly spot missing directories that might cause command-not-found errors.
3. **Optimization**: Detect empty path entries that might slow down command lookups.

## Note

An empty path entry (represented by '::' in the PATH) is often interpreted as the current directory. While sometimes intentional, this can pose security risks and is generally not recommended.
