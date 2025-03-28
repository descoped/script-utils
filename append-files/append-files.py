#!/usr/bin/env python3
import json
import os
import sys
import threading
from typing import List, Dict, Any, Tuple, Optional

import click
import pyperclip
import yaml
from tqdm import tqdm

# Import the transform functionality from extract-code-signatures.py
# Import handling that works with hyphenated filenames and is path independent
script_dir = os.path.dirname(os.path.abspath(__file__))

# Direct import with importlib for extract-code-signatures.py
import importlib.util

extract_file_path = os.path.join(script_dir, "extract-code-signatures.py")
if not os.path.exists(extract_file_path):
    # Try in same directory without script_dir prefix
    extract_file_path = "extract-code-signatures.py"

if os.path.exists(extract_file_path):
    spec = importlib.util.spec_from_file_location("extract_code_signatures", extract_file_path)
    if spec and spec.loader:
        extract_code_signatures = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(extract_code_signatures)
        transform_content = extract_code_signatures.transform_content
        SYSTEM_PROMPT = extract_code_signatures.SYSTEM_PROMPT
    else:
        def transform_content(content, transform_type):
            print(f"Warning: Could not load module from {extract_file_path}. Cannot transform to {transform_type}.",
                  file=sys.stderr)
            return content


        SYSTEM_PROMPT = """You are an expert Python programmer analyzing code files that include both
IDL (Interface Definition Language) declarations and Python implementations.
In these concatenated files, IDL declarations serve as interfaces or traits with type information,
 while the Python code contains the actual implementations.

When analyzing, use the IDL declarations as a guide to understand the intended design,
but focus primarily on the Python code. Your analysis should cover the overall purpose, module architecture,
key functions, and notable design decisions.
Emphasize practical insights that help developers understand and work with the code.

Key Points:

- Treat IDL declarations (with keywords like "function", "in", "returns", and "const") as Python interfaces 
  with type hints.
- Focus on the actual Python implementations for detailed analysis.
- Provide an analysis that is structured yet adaptable to various files and user-specific prompts.
"""
else:
    def transform_content(content, transform_type):
        print(
            f"Warning: extract-code-signatures.py not found at {extract_file_path}. Cannot transform to {transform_type}.",
            file=sys.stderr)
        return content


    SYSTEM_PROMPT = """You are an expert Python programmer analyzing code files that include both
IDL (Interface Definition Language) declarations and Python implementations.
In these concatenated files, IDL declarations serve as interfaces or traits with type information,
 while the Python code contains the actual implementations.

When analyzing, use the IDL declarations as a guide to understand the intended design,
but focus primarily on the Python code. Your analysis should cover the overall purpose, module architecture,
key functions, and notable design decisions.
Emphasize practical insights that help developers understand and work with the code.

Key Points:

- Treat IDL declarations (with keywords like "function", "in", "returns", and "const") as Python interfaces 
  with type hints.
- Focus on the actual Python implementations for detailed analysis.
- Provide an analysis that is structured yet adaptable to various files and user-specific prompts.
"""

# Default file extension to use when none is specified
default_extension = ".py"


def load_config_profile(profile_path: Optional[str] = None) -> Dict[str, Any]:
    """
    Load configuration from a profile file (JSON or YAML format).

    Args:
        profile_path (Optional[str]): Path to the configuration profile. If None,
                                     looks for .append-files in default locations.

    Returns:
        Dict[str, Any]: Configuration dictionary with CLI options.
    """
    if profile_path and profile_path.endswith(('.yml', '.yaml')):
        click.echo("Warning: YAML config file specified but PyYAML is not installed.", err=True)
        click.echo("Run: pip install pyyaml to enable YAML support.", err=True)

    # Default locations to check for config files
    default_locations = [
        ".append-files",  # Current directory
        ".append-files.json",  # JSON variant
        ".append-files.yaml",  # YAML variant
        ".append-files.yml",  # YAML variant
        os.path.expanduser("~/.append-files"),  # User's home directory
        os.path.expanduser("~/.append-files.json"),
        os.path.expanduser("~/.append-files.yaml"),
        os.path.expanduser("~/.append-files.yml"),
        os.path.expanduser("~/.config/append-files"),  # XDG config directory
        os.path.expanduser("~/.config/append-files.json"),
        os.path.expanduser("~/.config/append-files.yaml"),
        os.path.expanduser("~/.config/append-files.yml"),
    ]

    # If profile path is specified, use it
    if profile_path:
        if not os.path.isfile(profile_path):
            click.echo(f"Error: Configuration profile '{profile_path}' not found.", err=True)
            return {}
        config_paths = [profile_path]
    else:
        config_paths = default_locations

    # Try to load from each path
    for path in config_paths:
        if os.path.isfile(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    # Determine file format based on extension
                    if path.endswith(('.yml', '.yaml')):
                        config = yaml.safe_load(f)
                    else:
                        config = json.load(f)

                    if config is None:  # Empty YAML file
                        config = {}

                    click.echo(f"Loaded configuration from {path}")
                    return config
            except json.JSONDecodeError:
                click.echo(f"Error: JSON configuration file '{path}' contains invalid format.", err=True)
            except Exception as e:
                if 'yaml' in str(e).lower():
                    click.echo(f"Error: YAML configuration file '{path}' contains invalid format.", err=True)
                else:
                    click.echo(f"Error loading configuration from '{path}': {e}", err=True)

    # If we reach here, no config file was found or loaded
    if profile_path:
        click.echo(f"Error: Could not load configuration from '{profile_path}'.", err=True)

    return {}


def copy_to_clipboard(text: str) -> bool:
    """
    Copy the provided text to the clipboard.

    Args:
        text (str): The text to copy.

    Returns:
        bool: True if successful, False otherwise.
    """
    try:
        pyperclip.copy(text)
        return True
    except pyperclip.PyperclipException as e:
        click.echo(f"Error copying to clipboard: {e}", err=True)
        return False


def normalize_extensions(extensions: List[str]) -> List[str]:
    """
    Normalize file extensions by ensuring they start with a dot and are lowercase.

    Args:
        extensions (List[str]): A list of file extensions.

    Returns:
        List[str]: Normalized list of file extensions.
    """
    return ["." + ext.lower().lstrip(".") for ext in extensions]


def is_text_file(file_path: str) -> bool:
    """
    Check if a file is a text file by looking for null bytes.

    Args:
        file_path (str): The path to the file.

    Returns:
        bool: True if it's a text file, False otherwise.
    """
    try:
        with open(file_path, "rb") as f:
            chunk = f.read(1024)
            if b"\x00" in chunk:
                # Null byte detected; likely a binary file
                return False
        return True
    except Exception:
        # Any exception means we cannot read the file
        return False


def read_file_content(file_path: str) -> str:
    """
    Read the content of a text file using UTF-8 encoding.

    Args:
        file_path (str): The path to the file.

    Returns:
        str: The content of the file, or an empty string if unreadable.
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        # Skip files that cannot be decoded as UTF-8
        return ""
    except Exception as e:
        # Handle other exceptions silently
        return ""


def scan_files(
        input_paths: List[str],
        transform_paths: List[str],
        exclude_dirs: List[str],
        exclude_files: List[str],
        recursive: bool,
        default_extension: str,
        transform_format: str,
        input_paths_abs: set,
        all_files: List[Dict[str, Any]],
        list_files: bool,
):
    """
    Scan input paths and collect files to process.

    Args:
        input_paths (List[str]): Input files or directories with optional extensions.
        transform_paths (List[str]): Transform files or directories with optional extensions and transform type.
        exclude_dirs (List[str]): Directories to exclude.
        exclude_files (List[str]): Files to exclude.
        recursive (bool): Whether to scan directories recursively.
        default_extension (str): Default file extension to use.
        transform_format (str): Default transform format to use.
        input_paths_abs (set): Absolute paths of the input.
        all_files (List[Dict[str, Any]]): List to store file information.
        list_files (bool): Whether to print found files.
    """
    # Keep track of transformed files to avoid duplication
    transformed_files = set()

    # First, process transform paths to populate transformed_files set
    process_paths(
        transform_paths,
        exclude_dirs,
        exclude_files,
        recursive,
        default_extension,
        transform_format,  # Use the default transform format
        input_paths_abs,
        all_files,
        list_files,
        transformed_files,
    )

    # Then process regular input paths, skipping files that are already transformed
    process_paths(
        input_paths,
        exclude_dirs,
        exclude_files,
        recursive,
        default_extension,
        None,  # No transform for regular input paths
        input_paths_abs,
        all_files,
        list_files,
        transformed_files,
    )


def process_paths(
        paths: List[str],
        exclude_dirs: List[str],
        exclude_files: List[str],
        recursive: bool,
        default_extension: str,
        transform_format: Optional[str],
        paths_abs: set,
        all_files: List[Dict[str, Any]],
        list_files: bool,
        transformed_files: Optional[set] = None,
):
    """
    Process a list of paths and collect files to process.

    Args:
        paths (List[str]): Files or directories with optional extensions and transform type.
        exclude_dirs (List[str]): Directories to exclude.
        exclude_files (List[str]): Files to exclude.
        recursive (bool): Whether to scan directories recursively.
        default_extension (str): Default file extension to use.
        transform_format (Optional[str]): Default transform format to use.
        paths_abs (set): Absolute paths of the input.
        all_files (List[Dict[str, Any]]): List to store file information.
        list_files (bool): Whether to print found files.
        transformed_files (Optional[set]): Set of normalized file paths that have been transformed
    """
    if transformed_files is None:
        transformed_files = set()

    paths_to_scan: List[Tuple[str, List[str], Optional[str]]] = []
    index = 0  # Initialize index for file ordering

    for path_spec in paths:
        # Split path, extensions, and transform type if specified
        parts = path_spec.split(":", 2)
        path = parts[0]
        extensions = []
        transform_type = transform_format  # Use the provided default transform format

        if not os.path.exists(path):
            click.echo(f"Error: Path '{path}' does not exist.", err=True)
            continue

        if len(parts) > 1:
            # The second part can be either extensions or transform type
            if len(parts) > 2:
                # If we have 3 parts, the second is extensions and the third is transform type
                extensions = normalize_extensions(parts[1].split(","))
                transform_type = parts[2]
            else:
                # If we have 2 parts, check if the second part is a valid transform type
                if parts[1] in ["idl", "json"]:
                    transform_type = parts[1]
                else:
                    # Otherwise, it's extensions
                    extensions = normalize_extensions(parts[1].split(","))

        if not extensions:
            # Use default extension if none specified
            extensions = [default_extension]

        # Check if the path is hidden
        path_abspath = os.path.abspath(path)
        path_basename = os.path.basename(path_abspath)
        path_is_hidden = path_basename.startswith(".")

        # Skip hidden paths unless explicitly included
        if path_is_hidden and path_abspath not in paths_abs:
            continue

        if os.path.isfile(path):
            # Process individual file
            if any(os.path.basename(path) == ef for ef in exclude_files):
                continue
            if not is_text_file(path):
                continue

            # Normalize file path for comparison
            normalized_path = os.path.normpath(os.path.abspath(path))

            # Skip if the file is in the transformed_files set and we're not transforming
            if normalized_path in transformed_files and transform_type is None:
                continue

            # Add to transformed_files if we're transforming
            if transform_type is not None:
                transformed_files.add(normalized_path)

            if list_files:
                click.echo(f"Found file: {path}" +
                           (f" (with transform: {transform_type})" if transform_type else ""))
            all_files.append(
                {
                    "index": index,
                    "file_path": path,
                    "relative_path": os.path.basename(path),
                    "transform": transform_type,
                }
            )
            index += 1
        elif os.path.isdir(path):
            # Add directory to scan
            paths_to_scan.append((path, extensions, transform_type))
        else:
            click.echo(f"Error: '{path}' is not a file or directory.", err=True)
            continue

    # Scan directories
    for directory, extensions, transform_type in paths_to_scan:
        for root, dirs, files in os.walk(directory):
            if not recursive:
                dirs[:] = []  # Do not recurse into subdirectories

            # Exclude hidden directories unless explicitly included
            dirs[:] = [
                d
                for d in dirs
                if not d.startswith(".") or os.path.join(root, d) in paths_abs
            ]
            # Exclude specified directories
            dirs[:] = [d for d in dirs if d not in exclude_dirs]

            # Exclude hidden files
            files = [f for f in files if not f.startswith(".")]

            for file in files:
                if any(file == ef for ef in exclude_files):
                    continue
                if any(file.lower().endswith(ext) for ext in extensions):
                    file_path = os.path.join(root, file)
                    if not is_text_file(file_path):
                        continue

                    # Normalize file path for comparison
                    normalized_path = os.path.normpath(os.path.abspath(file_path))

                    # Skip if the file is in the transformed_files set and we're not transforming
                    if normalized_path in transformed_files and transform_type is None:
                        continue

                    # Add to transformed_files if we're transforming
                    if transform_type is not None:
                        transformed_files.add(normalized_path)

                    relative_path = os.path.relpath(file_path, directory)
                    if list_files:
                        click.echo(f"Found file: {file_path}" +
                                   (f" (with transform: {transform_type})" if transform_type else ""))
                    all_files.append(
                        {
                            "index": index,
                            "file_path": file_path,
                            "relative_path": relative_path,
                            "transform": transform_type,
                        }
                    )
                    index += 1


def consumer(
        all_files: List[Dict[str, Any]],
        append_content_list: List[Dict[str, Any]],
        header_template: str,
        footer_template: str,
        progress_bar,
        verbose_value: bool = False,
):
    """
    Process files from the shared list and append their content.

    Args:
        all_files (List[Dict[str, Any]]): Shared list of files to process.
        append_content_list (List[Dict[str, Any]]): Shared list to store processed content.
        header_template (str): Template for the header.
        footer_template (str): Template for the footer.
        progress_bar: Progress bar object.
        verbose_value (bool): Whether to print verbose output.
    """
    while True:
        try:
            # Retrieve file information
            file_info = all_files.pop()
        except IndexError:
            # No more files to process
            break
        file_path = file_info["file_path"]
        relative_path = file_info["relative_path"]
        index = file_info["index"]
        transform = file_info.get("transform")

        content = read_file_content(file_path)

        if content:
            # Apply transformation if specified
            if transform:
                try:
                    old_content = content
                    content = transform_content(content, transform)

                    # Detect if transformation had no effect
                    if content == old_content and verbose_value:
                        click.echo(f"Warning: Transformation to {transform} had no effect for {file_path}", err=True)
                except Exception as e:
                    click.echo(f"Error transforming {file_path} to {transform}: {e}", err=True)
                    if verbose_value:
                        import traceback
                        click.echo(traceback.format_exc(), err=True)

            # Apply header and footer
            header = header_template.format(filename=relative_path, filepath=file_path)
            footer = footer_template.format(filename=relative_path, filepath=file_path)
            append_content_list.append(
                {"index": index, "content": f"{header}{content}{footer}"}
            )
        if progress_bar is not None:
            # Update progress bar
            transform_info = f" ({transform})" if transform else ""
            progress_bar.set_postfix(file=f"{os.path.basename(file_path)}{transform_info}", refresh=False)
            progress_bar.update(1)


@click.command(context_settings={"max_content_width": 100})
@click.option(
    "--profile", "-p",
    help="Path to configuration profile (JSON or YAML)",
    default=None
)
@click.option(
    "--input",
    "-i",
    "input_paths",
    multiple=True,
    type=str,
    help="Input files or directories with extensions (e.g., file.py, dir/:ext1,ext2)",
)
@click.option(
    "--transform",
    "-t",
    "transform_paths",
    multiple=True,
    type=str,
    help="Transform files or directories with optional extensions and transform type (e.g., file.py:idl, dir/:py:json)",
)
@click.option(
    "--transform-format",
    type=click.Choice(["idl", "json"]),
    default="idl",
    help="Default transform format to use (default: idl)",
)
@click.option("--output-file", "-o", help="Name of the output file", show_default=True)
@click.option(
    "--clipboard",
    "-c",
    is_flag=True,
    help="Copy output to clipboard",
    show_default=True,
)
@click.option(
    "--exclude-dir",
    "-e",
    "exclude_dirs",
    multiple=True,
    default=[".git", "__pycache__", "venv", ".venv"],
    help="Directories to exclude from processing",
    show_default=True,
)
@click.option(
    "--exclude-file",
    "-x",
    "exclude_files",
    multiple=True,
    default=[],
    help="Files to exclude from processing",
    show_default=True,
)
@click.option(
    "--verbose", "-v", is_flag=True, help="Enable verbose output", show_default=True
)
@click.option(
    "--debug", is_flag=True, help="Enable debug mode with detailed error messages",
    show_default=True
)
@click.option(
    "--header-template",
    default="# File: {filename}\n\n",
    help="Custom header template",
    show_default="# File: {filename}\\n\\n",
)
@click.option(
    "--footer-template",
    default="\n\n",
    help="Custom footer template",
    show_default="\\n\\n",
)
@click.option(
    "--non-recursive",
    is_flag=True,
    help="Disable recursive directory traversal",
    show_default=True,
)
@click.option(
    "--default-extension",
    default=".py",
    help="Default file extension to use",
    show_default=True,
)
@click.option(
    "--skip-prompt",
    is_flag=True,
    help="Skip including system prompt with transform paths",
    show_default=True,
)
@click.pass_context
def main(
        ctx,
        profile,
        input_paths,
        transform_paths,
        transform_format,
        output_file,
        clipboard,
        exclude_dirs,
        exclude_files,
        verbose,
        debug,
        header_template,
        footer_template,
        non_recursive,
        default_extension,
        skip_prompt,
):
    """
    Append files and directories with specified extensions or directly from files.

    This script concatenates the contents of specified files and directories,
    applying optional headers and footers to each file's content. It can also
    transform file contents using various formats (e.g., IDL, JSON).

    When using transform paths, the system prompt is included by default.
    Use --skip-prompt to disable this behavior.

    Configuration profiles can be used to store common settings:
      - Default: .append-files[.json|.yaml|.yml] in the current directory
      - Home dir: ~/.append-files[.json|.yaml|.yml]
      - XDG config: ~/.config/append-files[.json|.yaml|.yml]
      - Use --profile to specify a custom configuration file

    YAML support requires PyYAML (pip install pyyaml)
    """
    # Enable debug mode if requested
    if debug:
        verbose = True
        import traceback
        sys.excepthook = lambda type, value, tb: traceback.print_exception(type, value, tb)

    # Load configuration profile if specified
    config = load_config_profile(profile)

    # Override config with command-line options where specified
    # Only use config values for options that weren't explicitly set on command line

    # For input_paths and transform_paths, we append to any values from the config
    # rather than overriding completely
    input_paths_list = list(input_paths)
    if not input_paths and "input_paths" in config:
        input_paths_list.extend(config.get("input_paths", []))

    transform_paths_list = list(transform_paths)
    if not transform_paths and "transform_paths" in config:
        transform_paths_list.extend(config.get("transform_paths", []))

    # For other options, use command-line if provided, otherwise use config value
    transform_format_value = transform_format or config.get("transform_format", "idl")
    output_file_value = output_file or config.get("output_file")
    clipboard_value = clipboard or config.get("clipboard", False)

    # For list-type options, merge with config unless explicitly provided
    exclude_dirs_list = list(exclude_dirs)
    if len(exclude_dirs) == 4 and all(d in [".git", "__pycache__", "venv", ".venv"] for d in exclude_dirs):
        # The default values were used, so we can override with config
        exclude_dirs_list = config.get("exclude_dirs", exclude_dirs_list)

    exclude_files_list = list(exclude_files)
    if len(exclude_files) == 0:
        # No exclude files specified, use config if available
        exclude_files_list = config.get("exclude_files", exclude_files_list)

    # For other scalar options, use command-line if provided, otherwise use config value
    verbose_value = verbose or config.get("verbose", False)
    header_template_value = header_template
    if header_template == "# File: {filename}\n\n":  # Default value
        header_template_value = config.get("header_template", header_template)

    footer_template_value = footer_template
    if footer_template == "\n\n":  # Default value
        footer_template_value = config.get("footer_template", footer_template)

    non_recursive_value = non_recursive or config.get("non_recursive", False)
    default_extension_value = default_extension
    if default_extension == ".py":  # Default value
        default_extension_value = config.get("default_extension", default_extension)

    # Determine whether to include system prompt - include by default with transforms
    # unless explicitly disabled with --skip-prompt
    skip_prompt_value = skip_prompt or config.get("skip_prompt", False)
    include_system_prompt = transform_paths_list and not skip_prompt_value

    # Now continue with the rest of the function using the merged options
    if not input_paths_list and not transform_paths_list:
        # Display help if no input or transform paths are provided
        click.echo(ctx.get_help())
        ctx.exit()

    recursive = not non_recursive_value
    # Convert input paths to absolute paths for comparison
    input_paths_abs = set()
    for p in input_paths_list:
        input_paths_abs.add(os.path.abspath(p.split(":", 1)[0]))
    for p in transform_paths_list:
        input_paths_abs.add(os.path.abspath(p.split(":", 1)[0]))

    all_files: List[Dict[str, Any]] = []  # List to store files to process
    append_content_list: List[Dict[str, Any]] = []  # List to store processed content

    click.echo("Scanning files...")

    # Scan and collect files to process
    scan_files(
        input_paths_list,
        transform_paths_list,
        exclude_dirs_list,
        exclude_files_list,
        recursive,
        default_extension_value,
        transform_format_value,
        input_paths_abs,
        all_files,
        verbose_value,
    )

    total_files = len(all_files)
    if total_files == 0:
        click.echo("No files to process.", err=True)
        return

    # Initialize the progress bar
    progress_bar = tqdm(
        total=total_files,
        desc="Processing files",
        unit="file",
        ncols=80,
        bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} files [{elapsed}<{remaining}]",
    )

    # Start consumer threads to process files concurrently
    num_consumers = 4  # Number of threads to use
    consumer_threads = []
    for _ in range(num_consumers):
        t = threading.Thread(
            target=consumer,
            args=(
                all_files,
                append_content_list,
                header_template_value,
                footer_template_value,
                progress_bar,
                verbose_value,
            ),
            daemon=True,
        )
        t.start()
        consumer_threads.append(t)

    # Wait for all threads to complete
    for t in consumer_threads:
        t.join()

    progress_bar.close()

    if not append_content_list:
        click.echo("No files processed.", err=True)
        return

    # Sort the content to maintain the original order
    append_content_list.sort(key=lambda x: x["index"])

    # Add system prompt if including transforms and not skipping prompt
    prefix = SYSTEM_PROMPT + "\n\n" if include_system_prompt else ""

    # Concatenate the content from all files
    append_content = prefix + "\n".join(item["content"] for item in append_content_list)

    if output_file_value:
        # Write the concatenated content to the specified output file
        try:
            with open(output_file_value, "w", encoding="utf-8") as output_file_:
                output_file_.write(append_content)
            click.echo(f"Appended files have been written to {output_file_value}")
        except Exception as e:
            click.echo(f"Error writing to file {output_file_value}: {e}", err=True)

    if clipboard_value:
        # Copy the concatenated content to the clipboard
        if copy_to_clipboard(append_content):
            click.echo("Appended content has been copied to clipboard")
        else:
            click.echo("Failed to copy content to clipboard", err=True)

    if not output_file_value and not clipboard_value:
        # Output the concatenated content to the console
        click.echo(append_content)


if __name__ == "__main__":
    main()
