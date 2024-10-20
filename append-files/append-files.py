import os
import click
import subprocess

default_extension = '.py'

def copy_to_clipboard_macos(text):
    try:
        process = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE, close_fds=True)
        process.communicate(text.encode('utf-8'))
        return True
    except Exception as e:
        print(f"Error copying to clipboard: {e}")
        return False

def append_files(input_paths):
    append_content = []
    
    for path_spec in input_paths:
        parts = path_spec.split(':')
        directory = parts[0]
        extensions = parts[1].split(',') if len(parts) > 1 else [default_extension]
        
        for root, _, files in os.walk(directory):
            for file in files:
                if any(file.endswith(ext) for ext in extensions):
                    file_path = os.path.join(root, file)
                    relative_path = os.path.relpath(file_path, directory)
                    
                    with open(file_path, 'r') as f:
                        content = f.read()
                    
                    append_content.append(f"# File: {relative_path}\n\n{content}\n\n")
    
    return '\n'.join(append_content)

@click.command()
@click.option('--input', '-i', 'input_paths', multiple=True, required=True, 
              help='Input directory and extensions (e.g., SOURCEDIR:ext1,ext2)')
@click.option('--output-file', '-o', help='Name of the output file')
@click.option('--clipboard', '-c', is_flag=True, help='Copy output to clipboard')
def main(input_paths, output_file, clipboard):
    """Append files with specified extensions from given directories."""
    append_content = append_files(input_paths)
    
    if output_file:
        with open(output_file, 'w') as output_file_:
            output_file_.write(append_content)
        click.echo(f"Appended files have been written to {output_file}")
    
    if clipboard:
        if copy_to_clipboard_macos(append_content):
            click.echo("Appended content has been copied to clipboard")
        else:
            click.echo("Failed to copy content to clipboard")
    
    if not output_file and not clipboard:
        click.echo(append_content)

if __name__ == '__main__':
    main()
    