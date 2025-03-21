# Secrets Sanitizer

Secrets Sanitizer is a utility script that identifies and obfuscates sensitive information in text files or clipboard
content. It's particularly useful for preparing logs, configuration files, or debug output for sharing publicly without
exposing API keys, passwords, tokens, or other secrets.

Each detected secret is replaced with a redacted placeholder, making it safe to share the content with support teams, in
public forums, or with AI assistants like Claude.

> **Note**: This script is written for macOS Terminal and is not tested for Linux or Windows.

## Installation

To install `secrets-sanitizer.sh`, use the following command:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | sh -s -- secrets-sanitizer
```

## Features

- Read from files or clipboard content
- Write sanitized output to files or clipboard
- Detects and obfuscates multiple types of secrets:
    - AWS Access and Secret Keys
    - Azure Connection Strings and Account Keys
    - Google API Keys and OAuth Client IDs
    - GitHub Tokens
    - Generic API Keys and Tokens
    - JWT Tokens
    - Passwords and Credentials
    - Private Keys (PEM format)
- Preserves the original structure of files while only redacting sensitive data
- Compatible with macOS (including Sequoia)

## Usage

Use the secrets-sanitizer.sh script to sanitize content based on the specified options:

### Options

- `-i, --input FILE`: Read from FILE instead of clipboard
- `-o, --output FILE`: Write to FILE instead of clipboard
- `-c, --clipboard`: Read from clipboard (default if no input file specified)
- `-r, --replace`: Replace clipboard content (default if no output file specified)
- `-v, --verbose`: Enable more detailed output
- `-h, --help`: Show help message and exit

### Usage Examples

Sanitize clipboard content and replace it with obfuscated version:

```bash
./secrets-sanitizer.sh
```

Read from a file and output to clipboard:

```bash
./secrets-sanitizer.sh -i credentials.log
```

Read from clipboard and write to a file:

```bash
./secrets-sanitizer.sh -o sanitized.txt
```

Read from one file and write to another:

```bash
./secrets-sanitizer.sh -i debug.log -o sanitized_debug.log
```

Verbose output with detailed information:

```bash
./secrets-sanitizer.sh -i config.json -v
```

## Testing

The repository includes a test script `test-secrets-sanitizer.sh` that generates sample data with various types of
secrets and runs the sanitizer in different configurations to verify functionality.

To run the tests:

```bash
./test-secrets-sanitizer.sh
```

This will:

1. Create sample files with randomly generated secrets
2. Run the sanitizer with different input/output combinations
3. Report the results of each test

## Notes

- **Original Structure Preservation**: The script preserves the original structure of your content, only replacing the
  actual secret values.
- **Detected Secret Types**: Currently detects AWS, Azure, Google, GitHub credentials, as well as generic API keys,
  JWTs, passwords, and private keys.
- **macOS Compatibility**: Specifically designed to work on macOS, including macOS Sequoia.

## Error Handling

If an error occurs while reading or processing files (e.g., due to permissions issues or invalid file paths), the script
will display an error message.

## Real-world Use Cases

- Preparing application logs for sharing with support
- Sanitizing configuration files before posting in public forums
- Cleaning debug output before sharing with colleagues
- Making content safe to share with AI assistants
- Ensuring no secrets are accidentally committed to version control
- 