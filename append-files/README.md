# Append Files: User Documentation

`append-files` is a utility for combining multiple code files into a single output, with optional code transformation capabilities. This documentation explains all concepts and features in detail.

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
| `-e, --exclude-dir TEXT` | Directories to exclude from processing |
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

## Advanced Usage Examples

### Basic concatenation with default Python extension
```bash
./append-files.sh -i src/ -o combined.py
```

### Multiple input paths with different extensions
```bash
./append-files.sh -i src/:py -i lib/:cpp,h -i config/:json -o project_files.txt
```

### Transform Python files to IDL format, copying to clipboard
```bash
./append-files.sh -t src/:py:idl -c
```

### Mixed regular and transformed inputs
```bash
./append-files.sh -i src/main.py -i README.md -t src/api/:idl -o project_overview.txt
```

### Using custom header/footer with template variables
```bash
./append-files.sh -i src/:py --header-template="// BEGIN {filepath} (Last edited: $(date))\n\n" --footer-template="\n// END {filepath}\n\n"
```

### Using a configuration profile with overrides
```bash
./append-files.sh -p my-profile.yaml -v --skip-prompt
```

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

### Error Handling

- Missing dependencies trigger automatic installation attempts
- Invalid or unreadable files are skipped
- Unicode errors are handled gracefully
- Binary files are automatically excluded

## Practical Use Cases

1. **Sharing code with AI assistants**: Create a single file with entire codebase for context
2. **Code documentation**: Generate interface documentation from implementation
3. **Code reviews**: Bundle related files for easier review 
4. **Project analysis**: Transform complex codebases to clearer representations
5. **Creating training data**: Prepare code samples in consistent format
