# Append Files

Append Files is a simple utility to append files from specified directories and file extensions into a single output file or clipboard. This tool is particularly useful for creating a single file that contains all sources, which can be helpful when you need to discuss or analyze code with Generative AI LLMs.

Each appended file's content is separated by a heading in the following format:

```
# File: path/to/file.py

..code..

# File: path/other/file.py

..code..
```

## Installation

To install `append-files.sh`, use the following command:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/install/install.sh | sh -s -- append-files
```

## Usage

Use the `append-files.sh` script to append files based on the specified options. The script allows you to specify input directories, file extensions, and the output destination (either a file, the console, or the clipboard on macOS).

### Options

* `-i, --input`: Input directory and file extensions (e.g., `SOURCE_DIR:ext1,ext2`). Multiple input options can be specified.  
* `-o, --output-file`: Output file where the appended content will be saved.  
* `-c, --clipboard`: Copy the appended content to the clipboard (macOS only).  

### Example Commands

This script appends the content of all Python files (.py) from a specified directory and prints the combined content to the console:

```bash
./append-files.sh -i /path/to/source:.py
```

Append multiple file types (e.g., `.py` and `.txt`) and output the result to a file:

```bash
./append-files.sh -i /path/to/source:.py,.txt -o append-output.txt
```

Append all .md files and copy the result to the clipboard (macOS only):

```bash
./append-files.sh -i /path/to/source:.md -c
```

## Error Handling

The script checks for the presence of Python and pip. If either is not installed, you will receive an error message.
If the Click library is missing, the script will install it automatically via pip.
