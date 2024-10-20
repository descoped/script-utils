# Combine Files

Combine Files is a simple utility to combine files from specified directories and file extensions into a single output file or clipboard. This tool is particularly useful for creating a single file that contains all sources, which can be helpful when you need to discuss or analyze code with Generative AI LLMs.

## Installation

To install `combine_files.sh`, use the following command:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/install/install.sh | sh -s -- combine-files
```

## Usage

Use the `combine_files.sh` script to combine files based on the specified options. The script allows you to specify input directories, file extensions, and the output destination (either a file, the console, or the clipboard on macOS).

### Options

* `-i, --input`: Input directory and file extensions (e.g., `SOURCE_DIR:ext1,ext2`). Multiple input options can be specified.  
* `-o, --output-file`: Output file where the combined content will be saved.  
* `-c, --clipboard`: Copy the combined content to the clipboard (macOS only).  

### Example Commands

Combine all Python files (.py) from a directory and print the combined content to the console:

```bash
./combine_files.sh -i /path/to/source:.py
```

Combine multiple file types (e.g., `.py` and `.txt`) and output the result to a file:

```bash
./combine_files.sh -i /path/to/source:.py,.txt -o combined_output.txt
```

Combine all .md files and copy the result to the clipboard (macOS only):

```bash
./combine_files.sh -i /path/to/source:.md -c
```

## Error Handling

The script checks for the presence of Python and pip. If either is not installed, you will receive an error message.
If the Click library is missing, the script will install it automatically via pip.
