# Append Files

Append Files is a utility script that appends files from specified directories and file extensions into a single output file or clipboard. This tool is particularly useful for creating a single file that contains all source code, which can be helpful when you need to discuss or analyze code with generative AI language models.

## Installation

To install `append-files.sh`, use the following command:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | sh -s -- append-files
```

Ensure that you have Python 3.7 or higher installed, along with the required Python packages (click, pyperclip, tqdm). The script will attempt to install missing packages automatically.

## Core Concepts

### File Concatenation

The primary purpose of `append-files` is to concatenate multiple files, preserving their content while adding headers and footers to identify each file's source. This is particularly useful for:

- Sharing code with AI assistants like ChatGPT or Claude
- Creating code documentation that includes source files
- Bundling related code files for analysis

### Transformation

Beyond simple concatenation, `append-files` can transform code files into different representations:

- **IDL (Interface Definition Language)**: Extracts code structure, focusing on function signatures, class definitions, and type information. Creates an interface-like representation that emphasizes structure over implementation details.
- **JSON**: Converts code into a structured JSON representation for programmatic analysis.

### System Prompt

When using transformations, a system prompt can be included that helps AI models understand the transformed code format. This prompt explains that IDL declarations serve as interfaces/traits with type information, while the Python code contains implementations.

## Command Structure

```
./append-files.sh [OPTIONS]
```

## Option Categories

### Input Options

| Option | Description |
|--------|-------------|
| `-i, --input PATH` | Specifies input files or directories with optional extensions. Format: `path[:ext1,ext2,...]` |
| `-t, --transform PATH` | Similar to input, but applies transformation. Format: `path[:ext1,ext2,...][:{idl|json}]` |
| `--transform-format [idl\|json]` | Default transform format when not specified in `-t` |

### Output Options

| Option | Description |
|--------|-------------|
| `-o, --output-file TEXT` | Writes output to specified file |
| `-c, --clipboard` | Copies output to clipboard |

### Filtering Options

| Option | Description |
|--------|-------------|
| `-e, --exclude-dir TEXT` | Directories to exclude from processing (default: .git, __pycache__) |
| `-x, --exclude-file TEXT` | Files to exclude from processing |
| `--non-recursive` | Disables recursive directory traversal |
| `--default-extension TEXT` | Default file extension when not specified (default: `.py`) |

### Formatting Options

| Option | Description |
|--------|-------------|
| `--header-template TEXT` | Template for file headers (default: `# File: {filename}\n\n`) |
| `--footer-template TEXT` | Template for file footers (default: `\n\n`) |
| `--skip-prompt` | Disables inclusion of system prompt with transform paths |

### Configuration Options

| Option | Description |
|--------|-------------|
| `-p, --profile TEXT` | Path to configuration profile file (JSON or YAML) |

### Miscellaneous Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Enables verbose output |
| `--help` | Shows help message and exits |

## Path Specification Details

The tool uses a flexible path specification format that combines paths with extensions and transform types:

### Input Paths (`-i, --input`)

- `file.py` - Include a specific file
- `dir/` - Include all Python files (default extension) in directory
- `dir/:js,ts` - Include all JavaScript and TypeScript files in directory

### Transform Paths (`-t, --transform`)

- `file.py:idl` - Transform a specific file to IDL format
- `dir/:idl` - Transform all Python files to IDL format
- `dir/:js,ts:json` - Transform all JavaScript and TypeScript files to JSON format
- `dir/:py:idl` - Transform all Python files to IDL format

## Usage Examples

### Basic Usage

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

### Advanced Usage Examples

Basic concatenation with default Python extension:
```bash
./append-files.sh -i src/ -o combined.py
```

Multiple input paths with different extensions:
```bash
./append-files.sh -i src/:py -i lib/:cpp,h -i config/:json -o project_files.txt
```

Transform Python files to IDL format, copying to clipboard:
```bash
./append-files.sh -t src/:py:idl -c
```

Mixed regular and transformed inputs:
```bash
./append-files.sh -i src/main.py -i README.md -t src/api/:idl -o project_overview.txt
```

Using custom header/footer with template variables:
```bash
./append-files.sh -i src/:py --header-template="// BEGIN {filepath} (Last edited: $(date))\n\n" --footer-template="\n// END {filepath}\n\n"
```

Using a configuration profile with overrides:
```bash
./append-files.sh -p my-profile.yaml -v --skip-prompt
```

## Understanding Transformation

### IDL Transformation

IDL transformation extracts code structure, producing a representation that:

1. Shows module-level docstrings as comments
2. Lists imports
3. Defines constants and global variables
4. Lists functions with parameters, return types, and docstrings
5. Defines classes as interfaces with their methods and properties

Example:
```
// Module docstring as comments
import module_name;
import other_module.specific_function;

const MY_CONSTANT = 42;

// Function docstring as comments
function my_function(in str name, in int count) returns List[str];

interface MyClass extends BaseClass {
  // Class docstring as comments
  const CLASS_VAR = "value";
  
  constructor(str name, int value);
  
  my_method(in List[str] items) returns bool;
  
  static static_method(in int value) returns void;
};
```

### JSON Transformation

JSON transformation produces a structured representation of code elements including:
- Module information
- Imports
- Global variables
- Function definitions with parameters and return types
- Class definitions with inheritance, methods, and class variables

This format is meant for programmatic analysis rather than human reading.

## Configuration Profiles

Configuration profiles allow storing common settings in JSON or YAML format:

```yaml
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
  - node_modules

exclude_files:
  - setup.py
  - __init__.py

header_template: "# File: {filename}\n\n"
footer_template: "\n\n"
default_extension: .py
skip_prompt: false
verbose: false
non_recursive: false
```

Configuration profiles are searched in:
1. Current directory: `.append-files[.json|.yaml|.yml]`
2. Home directory: `~/.append-files[.json|.yaml|.yml]`
3. XDG config: `~/.config/append-files[.json|.yaml|.yml]`
4. Custom path specified with `--profile`

## Notes

- **Header and Footer Templates**: The `--header-template` and `--footer-template` options allow you to customize the header and footer for each file's content. You can use `{filename}` and `{filepath}` as placeholders.
- **Hidden Files and Directories**: The script excludes hidden files and directories (those starting with a dot) by default.
- **Unicode Support**: The script reads and writes files using UTF-8 encoding to handle Unicode characters properly.

## Implementation Details

### File Processing Flow

1. Scan input directories and collect files matching specified extensions
2. Filter files based on exclusion patterns
3. Read file content with UTF-8 encoding
4. Apply transformations if specified
5. Add headers and footers
6. Combine content in original order
7. Output to specified destination (file, clipboard, or console)

### Multi-threading

The tool uses multi-threading to process files concurrently, improving performance with large file sets.

## Error Handling

The script checks for the presence of Python 3.7 or higher. If the required version is not installed, you will receive an error message.

The script also checks for required Python packages (click, pyperclip, tqdm, mimetypes). If any are missing, the script will attempt to install them automatically using pip.

If an error occurs while reading or writing files (e.g., due to permission issues or invalid file paths), the script will display an error message and continue processing other files.

- Missing dependencies trigger automatic installation attempts
- Invalid or unreadable files are skipped
- Unicode errors are handled gracefully
- Binary files are automatically excluded

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

## Practical Use Cases

1. **Sharing code with AI assistants**: Create a single file with entire codebase for context
2. **Code documentation**: Generate interface documentation from implementation
3. **Code reviews**: Bundle related files for easier review 
4. **Project analysis**: Transform complex codebases to clearer representations
5. **Creating training data**: Prepare code samples in consistent format
