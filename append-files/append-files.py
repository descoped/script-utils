#!/usr/bin/env python3
import os
import sys
import threading
from typing import List, Dict, Any, Tuple, Optional

import click
import pyperclip
from tqdm import tqdm

# Import the transform functionality from extract-code-signatures.py
# Check if the script is in the same directory or in PYTHONPATH
try:
    # First try direct import
    from extract_code_signatures import transform_content, SYSTEM_PROMPT
except ImportError:
    # If that fails, try to find the script in the same directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if script_dir not in sys.path:
        sys.path.append(script_dir)
    try:
        # Try with underscores (Python module naming convention)
        from extract_code_signatures import transform_content, SYSTEM_PROMPT
    except ImportError:
        # Try with the exact filename
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "extract_code_signatures",
            os.path.join(script_dir, "extract-code-signatures.py")
        )
        if spec and spec.loader:
            extract_code_signatures = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(extract_code_signatures)
            transform_content = extract_code_signatures.transform_content
            SYSTEM_PROMPT = extract_code_signatures.SYSTEM_PROMPT
        else:
            # Define fallback versions if import fails
            def transform_content(content, transform_type):
                print(f"Warning: extract-code-signatures.py not found. Cannot transform to {transform_type}.",
                      file=sys.stderr)
                return content


            SYSTEM_PROMPT = """System Prompt:
You are an expert Python programmer analyzing code files that include both
IDL (Interface Definition Language) declarations and Python implementations."""

# Default file extension to use when none is specified
default_extension = ".py"


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
    # Process regular input paths
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
    )

    # Process transform paths
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
    """
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
):
    """
    Process files from the shared list and append their content.

    Args:
        all_files (List[Dict[str, Any]]): Shared list of files to process.
        append_content_list (List[Dict[str, Any]]): Shared list to store processed content.
        header_template (str): Template for the header.
        footer_template (str): Template for the footer.
        progress_bar: Progress bar object.
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
                    content = transform_content(content, transform)
                except Exception as e:
                    click.echo(f"Error transforming {file_path} to {transform}: {e}", err=True)

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
    "--include-system-prompt",
    is_flag=True,
    help="Include system prompt for IDL transformations",
    show_default=True,
)
@click.pass_context
def main(
        ctx,
        input_paths,
        transform_paths,
        transform_format,
        output_file,
        clipboard,
        exclude_dirs,
        exclude_files,
        verbose,
        header_template,
        footer_template,
        non_recursive,
        default_extension,
        include_system_prompt,
):
    """
    Append files and directories with specified extensions or directly from files.

    This script concatenates the contents of specified files and directories,
    applying optional headers and footers to each file's content. It can also
    transform file contents using various formats (e.g., IDL, JSON).
    """
    if not input_paths and not transform_paths:
        # Display help if no input or transform paths are provided
        click.echo(ctx.get_help())
        ctx.exit()

    recursive = not non_recursive
    # Convert input paths to absolute paths for comparison
    input_paths_abs = set()
    for p in input_paths:
        input_paths_abs.add(os.path.abspath(p.split(":", 1)[0]))
    for p in transform_paths:
        input_paths_abs.add(os.path.abspath(p.split(":", 1)[0]))

    all_files: List[Dict[str, Any]] = []  # List to store files to process
    append_content_list: List[Dict[str, Any]] = []  # List to store processed content

    click.echo("Scanning files...")

    # Scan and collect files to process
    scan_files(
        input_paths,
        transform_paths,
        exclude_dirs,
        exclude_files,
        recursive,
        default_extension,
        transform_format,
        input_paths_abs,
        all_files,
        verbose,
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
                header_template,
                footer_template,
                progress_bar,
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

    # Add system prompt if requested
    prefix = SYSTEM_PROMPT + "\n\n" if include_system_prompt else ""

    # Concatenate the content from all files
    append_content = prefix + "\n".join(item["content"] for item in append_content_list)

    if output_file:
        # Write the concatenated content to the specified output file
        try:
            with open(output_file, "w", encoding="utf-8") as output_file_:
                output_file_.write(append_content)
            click.echo(f"Appended files have been written to {output_file}")
        except Exception as e:
            click.echo(f"Error writing to file {output_file}: {e}", err=True)

    if clipboard:
        # Copy the concatenated content to the clipboard
        if copy_to_clipboard(append_content):
            click.echo("Appended content has been copied to clipboard")
        else:
            click.echo("Failed to copy content to clipboard", err=True)

    if not output_file and not clipboard:
        # Output the concatenated content to the console
        click.echo(append_content)


if __name__ == "__main__":
    main()
