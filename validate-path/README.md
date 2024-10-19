# Path Configuration Validation

This repository contains two shell scripts to help you validate and analyze your terminal's PATH configuration.

## Scripts

1. `validate-path.sh`: Validates your PATH environment variable.
2. `analyze-path.sh`: Analyzes shell configuration files for PATH modifications.

## validate-path.sh

Checks each directory in your PATH to determine if it exists and detects empty entries.

### Usage

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/validate-path/validate-path.sh | sh
```

### Output

- `<path> exists`: Directory exists
- `<path> does not exist`: Directory doesn't exist
- `Empty (::) path exists`: Empty path entry detected

## analyze-path.sh

Parses shell configuration files (for Zsh or Bash) to locate PATH modifications.

### Usage

```zsh
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/validate-path/analyze-path.sh | zsh
```

#### Verbose

```zsh
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/refs/heads/master/validate-path/analyze-path.sh | zsh -s - -v
```

### Output

- Config file
- Line number
- Line content for PATH modifications

## Why Use These Scripts?

1. **Security**: Identify unexpected directories or modifications in PATH
2. **Troubleshooting**: Spot configuration issues causing command-not-found errors
3. **Optimization**: Detect redundant or inefficient PATH configurations

## Note

Empty path entries ('::') often represent the current directory, which may pose security risks.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.