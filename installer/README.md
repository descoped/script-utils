# Install Script Utility

A script utility designed to download and install scripts from module repositories using a configuration file. Primarily used to manage installations across multiple repositories.

## Installation

To use this script, run the following command from the remote repository where your module is located. The script will download and install files based on the provided configuration file.

### Example Usage:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | sh -s -- <module_name>
```

## Configuration File

The script downloads a configuration file `install.yml` from the remote repository. This file specifies the list of files to install and their destinations within your local file system.

### Example `install.yml`:

```yaml
- file: file1.sh          # file to install
  executable: true        # make executable
- file: file2.sh          # other file to install
  destination: tools      # relative destination: tools
- file: README.md         # install file
  destination: docs       # relative destination: docs
```

## Features

* **Remote File Installation**: Downloads files from a remote repository and installs them based on the configuration in the `install.yml` file
* **Customizable Installation Directory**: By default, files are installed in `$HOME/bin`, but you can specify a custom directory
* **Executable Permissions**: Files marked as `executable: true` in the configuration file are automatically given executable permissions
* **ANSI Colored Logging**: The script uses colored log messages for clarity, with different log levels (INFO, DEBUG, WARNING, ERROR)

## Running the Script

1. **Download and Install**: Run the script with the module name from the remote repository
2. **Specify Custom Directory (Optional)**: Use the `INSTALL_DIR` variable to change the default installation directory

### Command to Install:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | sh -s -- <module_name>
```

### Custom Directory Example:

```bash
curl -sSL https://raw.githubusercontent.com/descoped/script-utils/master/installer/install.sh | INSTALL_DIR=/custom/path sh -s -- <module_name>
```

## Log Levels

* **INFO**: Displays general process information (Green)
* **DEBUG**: Shows detailed debugging information (Blue)
* **WARNING**: Alerts for potential issues (Yellow)
* **ERROR**: Reports critical errors (Red)

## Installation Confirmation

Before proceeding with the installation, the script displays an installation plan and prompts for your confirmation.
