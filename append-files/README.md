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
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/install/install.sh | sh -s -- append-files
```

Ensure that you have Python 3.7 or higher installed, along with the required Python packages (click, pyperclip, tqdm). The script will attempt to install missing packages automatically.

## Usage

Use the append-files.sh script to append files based on the specified options. The script allows you to specify input files and directories, file extensions, and the output destination (either a file, the console, or the clipboard).

### Options

- `-i, --input PATH`: Input files or directories with extensions (e.g., file.py, dir/:ext1,ext2). Multiple input options can be specified.
- `-o, --output-file TEXT`: Name of the output file.
- `-c, --clipboard`: Copy output to clipboard.
- `-e, --exclude-dir TEXT`: Directories to exclude from processing (default: .git, __pycache__).
- `-x, --exclude-file TEXT`: Files to exclude from processing.
- `-v, --verbose`: Enable verbose output.
- `--header-template TEXT`: Custom header template (default: # File: {filename}\n\n).
- `--footer-template TEXT`: Custom footer template (default: \n\n).
- `--non-recursive`: Disable recursive directory traversal.
- `--default-extension TEXT`: Default file extension to use (default: .py).
- `--help`: Show help message and exit.

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

Disable recursive traversal:
```bash
./append-files.sh -i scripts/ --non-recursive
```

Specify default extension:
```bash
./append-files.sh -i scripts/ --default-extension='.sh'
```

## Notes

- **Header and Footer Templates**: The `--header-template` and `--footer-template` options allow you to customize the header and footer for each file's content. You can use `{filename}` and `{filepath}` as placeholders.
- **Hidden Files and Directories**: The script excludes hidden files and directories (those starting with a dot) by default.
- **Unicode Support**: The script reads and writes files using UTF-8 encoding to handle Unicode characters properly.

## Error Handling

The script checks for the presence of Python 3.7 or higher. If the required version is not installed, you will receive an error message.

The script also checks for required Python packages (click, pyperclip, tqdm, mimetypes). If any are missing, the script will attempt to install them automatically using pip.

If an error occurs while reading or writing files (e.g., due to permission issues or invalid file paths), the script will display an error message and continue processing other files.

## Dependencies

Make sure to have the following Python packages installed:

- click
- pyperclip
- tqdm
- mimetypes (usually included with Python)

You can install the required packages using:

```bash
pip install click pyperclip tqdm
```

