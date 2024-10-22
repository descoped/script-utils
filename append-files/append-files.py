#!/usr/bin/env python3
import os
import sys
import click
import subprocess
import pyperclip
from tqdm import tqdm
import mimetypes
from typing import List

default_extension = '.py'


def copy_to_clipboard(text: str) -> bool:
    try:
        pyperclip.copy(text)
        return True
    except pyperclip.PyperclipException as e:
        click.echo(f"Error copying to clipboard: {e}", err=True)
        return False


def normalize_extensions(extensions: List[str]) -> List[str]:
    return ['.' + ext.lower().lstrip('.') for ext in extensions]


def is_text_file(file_path: str) -> bool:
    mime_type, _ = mimetypes.guess_type(file_path)
    return mime_type is None or mime_type.startswith('text/')


def append_files(input_paths: List[str], exclude_dirs: List[str], exclude_files: List[str],
                 header_template: str, footer_template: str, recursive: bool,
                 default_extension: str, verbose: bool) -> str:
    append_content = []

    for path_spec in input_paths:
        if os.path.isfile(path_spec):
            if any(os.path.basename(path_spec) == ef for ef in exclude_files):
                continue
            if not is_text_file(path_spec):
                continue
            try:
                with open(path_spec, 'r', encoding='utf-8') as f:
                    content = f.read()
                header = header_template.format(filename=os.path.basename(path_spec), filepath=path_spec)
                footer = footer_template.format(filename=os.path.basename(path_spec), filepath=path_spec)
                append_content.append(f"{header}{content}{footer}")
                if verbose:
                    click.echo(f"Processed file: {path_spec}")
            except Exception as e:
                click.echo(f"Error reading file {path_spec}: {e}", err=True)
        else:
            # Handle directory with optional extensions
            parts = path_spec.split(':')
            directory = parts[0]
            if len(parts) > 1:
                extensions = normalize_extensions(parts[1].split(','))
            else:
                extensions = [default_extension]

            if not directory:
                click.echo(f"Error: Directory path is empty in '{path_spec}'", err=True)
                continue

            directory = str(directory)

            for root, dirs, files in os.walk(directory):
                if not recursive:
                    dirs[:] = []  # Don't recurse into subdirectories
                # Exclude specified directories
                dirs[:] = [d for d in dirs if not d.startswith('.') and d not in exclude_dirs]

                files = [f for f in files if not f.startswith('.')]

                for file in tqdm(files, desc=f"Processing {root}", disable=not verbose):
                    if any(file == ef for ef in exclude_files):
                        continue
                    if any(file.lower().endswith(ext) for ext in extensions):
                        file_path = os.path.join(root, file)
                        if not is_text_file(file_path):
                            continue
                        relative_path = os.path.relpath(str(file_path), str(directory))
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                content = f.read()
                            header = header_template.format(filename=relative_path, filepath=file_path)
                            footer = footer_template.format(filename=relative_path, filepath=file_path)
                            append_content.append(f"{header}{content}{footer}")
                            if verbose:
                                click.echo(f"Processed file: {file_path}")
                        except Exception as e:
                            click.echo(f"Error reading file {file_path}: {e}", err=True)
    return '\n'.join(append_content)


@click.command(context_settings={'max_content_width': 100})
@click.option('--input', '-i', 'input_paths', multiple=True,
              type=click.Path(exists=True),
              help='Input files or directories with extensions (e.g., file.py, dir/:ext1,ext2)')
@click.option('--output-file', '-o', help='Name of the output file', show_default=True)
@click.option('--clipboard', '-c', is_flag=True, help='Copy output to clipboard', show_default=True)
@click.option('--exclude-dir', '-e', 'exclude_dirs', multiple=True, default=['.git', '__pycache__'],
              help='Directories to exclude from processing', show_default=True)
@click.option('--exclude-file', '-x', 'exclude_files', multiple=True, default=[],
              help='Files to exclude from processing', show_default=True)
@click.option('--verbose', '-v', is_flag=True, help='Enable verbose output', show_default=True)
@click.option('--header-template', default='# File: {filename}\n\n',
              help='Custom header template',
              show_default='# File: {filename}\\n\\n')
@click.option('--footer-template', default='\n\n',
              help='Custom footer template',
              show_default='\\n\\n')
@click.option('--non-recursive', is_flag=True, help='Disable recursive directory traversal', show_default=True)
@click.option('--default-extension', default='.py', help='Default file extension to use', show_default=True)
@click.pass_context
def main(ctx, input_paths, output_file, clipboard, exclude_dirs, exclude_files, verbose,
         header_template, footer_template, non_recursive, default_extension):
    """
    Append files and directories with specified extensions or directly from files.
    """
    if not input_paths:
        click.echo(ctx.get_help())
        ctx.exit()

    append_content = append_files(
        input_paths, exclude_dirs, exclude_files, header_template, footer_template,
        not non_recursive, default_extension, verbose
    )

    if output_file:
        try:
            with open(output_file, 'w', encoding='utf-8') as output_file_:
                output_file_.write(append_content)
            click.echo(f"Appended files have been written to {output_file}")
        except Exception as e:
            click.echo(f"Error writing to file {output_file}: {e}", err=True)

    if clipboard:
        if copy_to_clipboard(append_content):
            click.echo("Appended content has been copied to clipboard")
        else:
            click.echo("Failed to copy content to clipboard", err=True)

    if not output_file and not clipboard:
        click.echo(append_content)


if __name__ == '__main__':
    main()
