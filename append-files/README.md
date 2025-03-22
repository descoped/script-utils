# Append Files

Append Files is a utility script that appends files from specified directories and file extensions into a single output file or clipboard. This tool is particularly useful for creating a single file that contains all source code, which can be helpful when you need to discuss or analyze code with generative AI language models.

Each appended file's content is separated by a customizable header and footer. By default, the header is:

```
# File: path/to/file.py
```

And the footer is a blank line.

## Installation

To install `append-files.sh`, use the following command:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | sh -s -- append-files
```

Ensure that you have Python 3.7 or higher installed, along with the required Python packages (click, pyperclip, tqdm, pyyaml). The script will attempt to install missing packages automatically.

## Usage

Use the append-files.sh script to append files based on the specified options. The script allows you to specify input files and directories, file extensions, and the output destination (either a file, the console, or the clipboard).

### Options

- `-p, --profile TEXT`: Path to configuration profile (JSON or YAML).
- `-i, --input PATH`: Input files or directories with extensions (e.g., file.py, dir/:ext1,ext2). Multiple input options can be specified.
- `-t, --transform PATH`: Transform files or directories with optional extensions and transform type (e.g., file.py:idl, dir/:py:json).
- `--transform-format [idl|json]`: Default transform format to use (default: idl).
- `-o, --output-file TEXT`: Name of the output file.
- `-c, --clipboard`: Copy output to clipboard.
- `-e, --exclude-dir TEXT`: Directories to exclude from processing (default: .git, __pycache__, venv, .venv).
- `-x, --exclude-file TEXT`: Files to exclude from processing.
- `-v, --verbose`: Enable verbose output.
- `--header-template TEXT`: Custom header template (default: # File: {filename}\n\n).
- `--footer-template TEXT`: Custom footer template (default: \n\n).
- `--non-recursive`: Disable recursive directory traversal.
- `--default-extension TEXT`: Default file extension to use (default: .py).
- `--include-system-prompt`: Include system prompt for IDL transformations.
- `--help`: Show help message and exit.

### Configuration Profiles

You can save common command-line options in configuration profiles using YAML or JSON format. This allows you to reuse settings without typing lengthy command lines.

#### Profile Locations

The tool checks for configuration profiles in the following locations:
- `.append-files`, `.append-files.json`, `.append-files.yaml`, or `.append-files.yml` in the current directory
- `~/.append-files`, `~/.append-files.json`, `~/.append-files.yaml`, or `~/.append-files.yml` in your home directory
- `~/.config/append-files`, `~/.config/append-files.json`, `~/.config/append-files.yaml`, or `~/.config/append-files.yml` in your config directory

You can also specify a custom profile path using the `--profile` option.

#### Example Configuration (YAML)

Configuration files can be created in either YAML or JSON format following the same structure. Here's an example in YAML:

```yaml
# Append Files Configuration
input_paths:
  - src/
  - lib/:py,cpp,h

transform_paths:
  - proto/:py:idl

transform_format: idl

exclude_dirs:
  - .git
  - __pycache__
  - venv
  - .venv
  - node_modules

exclude_files:
  - setup.py
  - __init__.py

header_template: "# File: {filename}\n\n"
footer_template: "\n\n"
default_extension: .py
include_system_prompt: true
verbose: false
non_recursive: false
```

JSON format follows the same structure but with JSON syntax.

#### Profile Usage

Use a profile without specifying any additional options:
```bash
./append-files.sh
```

Override profile settings with command-line options:
```bash
./append-files.sh --transform-format json
```

Use a custom profile:
```bash
./append-files.sh --profile my-settings.yaml
```

### Usage Examples

Append specific files and output to console:
```bash
./append-files.sh -i file1.py -i file2.py
```

Append files from a directory with specific extensions and output to a file:
```bash
./append-files.sh -i src/:py,txt -o combined.txt
```

Copy appended content to clipboard with verbose output:
```bash
./append-files.sh -i src/:py -c -v
```

Exclude specific directories and files:
```bash
./append-files.sh -i src/ -e tests -e legacy_code -x ignore_this.py
```

Use custom header and footer templates:
```bash
./append-files.sh -i src/:py --header-template='// Start of {filename}\n' --footer-template='// End of {filename}\n' -o combined.cpp
```

Transform Python files to IDL format:
```bash
./append-files.sh -t src/:py:idl -o api.idl
```

## Notes

- **Header and Footer Templates**: The `--header-template` and `--footer-template` options allow you to customize the header and footer for each file's content. You can use `{filename}` and `{filepath}` as placeholders.
- **Hidden Files and Directories**: The script excludes hidden files and directories (those starting with a dot) by default.
- **Unicode Support**: The script reads and writes files using UTF-8 encoding to handle Unicode characters properly.
- **Configuration Precedence**: Command-line options take precedence over configuration profile settings, which take precedence over default values.

## Error Handling

The script checks for the presence of Python 3.7 or higher. If the required version is not installed, you will receive an error message.

The script also checks for required Python packages (click, pyperclip, tqdm, pyyaml). If any are missing, the script will attempt to install them automatically using pip.

If an error occurs while reading or writing files (e.g., due to permission issues or invalid file paths), the script will display an error message and continue processing other files.

## Dependencies

Make sure to have the following Python packages installed:

- click
- pyperclip
- tqdm
- pyyaml (optional, for YAML configuration files)

You can install the required packages using:

```bash
pip install click pyperclip tqdm pyyaml
```