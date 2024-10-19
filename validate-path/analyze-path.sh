#!/usr/bin/env zsh

# Enable extended globbing
setopt extendedglob

# ANSI color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false                # Flag for verbose output
PROCESSED_FILES=()           # Array to track processed files (prevents circular references)
COMPUTED_PATH=()             # Array-based computed PATH
SIMPLE_COMPUTED_PATH="$PATH" # String-based computed PATH (simpler method)
UNDEFINED_VARIABLES=()       # Array to track undefined variables encountered
typeset -A SIMULATED_ENV     # Associative array to simulate environment variables
typeset -A PATH_ENTRY_SOURCES # Associative array to track sources of PATH entries
typeset -A PATH_ENTRY_COUNTS  # Associative array to count occurrences of PATH entries

# Initialize essential environment variables
SIMULATED_ENV[PATH]="$PATH"
SIMULATED_ENV[HOME]="$HOME"

# Function to check if output is being piped
is_piped() {
    [[ ! -t 1 ]]
}

# Function to echo colored output
echo_color() {
    local level=$1
    local message=$2
    local color

    # Assign color based on message level
    case $level in
        INFO)    color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        ERROR)   color=$RED ;;
        VERBOSE) color=$BLUE ;;
        *)       color=$NC ;;
    esac

    # If output is piped, don't use colors
    if is_piped; then
        echo "[$level] $message"
    else
        echo -e "${color}[$level] $message${NC}"
    fi
}

# Function to log messages based on verbosity level
log_message() {
    local level=$1
    local message=$2

    # Exclude lines that may contain sensitive information
    if [[ "$message" == *'PASSWORD'* || "$message" == *'TOKEN'* || "$message" == *'SECRET'* ]]; then
        message="[REDACTED] Sensitive information omitted."
    fi

    if [[ "$VERBOSE" == true ]] || [[ "$level" != "VERBOSE" ]]; then
        echo_color "$level" "$message"
    fi
}

# Function to check if an environment variable is set
check_variable() {
    local var_name="$1"
    if [[ -z "${SIMULATED_ENV[$var_name]}" ]]; then
        UNDEFINED_VARIABLES+=("$var_name")
        log_message WARNING "Environment variable '$var_name' is not set. It might be defined later in the file."
        return 1
    fi
    return 0
}

# Function to safely expand variables in a string using simulated environment
expand_variables() {
    local input="$1"
    local output="$input"
    local var_pattern='\$\{?([a-zA-Z_][a-zA-Z0-9_]*)\}?'

    while [[ "$output" =~ $var_pattern ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${SIMULATED_ENV[$var_name]}"
        if [[ -z "$var_value" ]]; then
            UNDEFINED_VARIABLES+=("$var_name")
            log_message WARNING "Environment variable '$var_name' is not set. Skipping part: $input"
            output=""
            break
        else
            output="${output//\$\{${var_name}\}/$var_value}"
            output="${output//\$${var_name}/$var_value}"
        fi
    done

    echo "$output"
}

# Function to resolve and normalize file paths
resolve_path() {
    local path="$1"
    local base_dir="$2"

    # Expand tilde to $HOME
    path="${path/#\~/${SIMULATED_ENV[HOME]}}"

    # Expand variables in the path
    path=$(expand_variables "$path")
    if [[ -z "$path" ]]; then
        echo ""
        return
    fi

    # If path is relative, make it absolute using the base directory
    if [[ "$path" != /* && -n "$base_dir" ]]; then
        path="$base_dir/$path"
    fi

    # Use realpath or readlink to resolve the path, if available
    if command -v realpath >/dev/null 2>&1; then
        path=$(realpath -e "$path" 2>/dev/null) || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        path=$(readlink -f "$path" 2>/dev/null) || echo "$path"
    else
        # Fallback method using Zsh parameter expansions
        local dir="${path:h}"
        local base="${path:t}"
        if [[ -d "$dir" ]]; then
            path="$(cd "$dir" && pwd)/$base"
        else
            path="$path"
        fi
    fi

    echo "$path"
}

# Main function to process a configuration file
process_file() {
    local file=$1

    log_message VERBOSE "Attempting to process file: $file"

    # Check if file exists
    if [[ ! -f "$file" ]]; then
        log_message VERBOSE "File $file does not exist. Skipping."
        return
    fi

    # Check for circular references
    if [[ " ${PROCESSED_FILES[*]} " == *" ${file} "* ]]; then
        log_message WARNING "Circular reference detected for $file. Skipping to prevent infinite loop."
        return
    fi

    PROCESSED_FILES+=("$file")

    log_message INFO "Processing file: $file"

    local line_number=0

    # Process the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))

        # Trim leading and trailing whitespace
        local trimmed_line="${line#"${line%%[![:space:]]*}"}"
        trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"

        # Skip empty lines
        if [[ -z "$trimmed_line" ]]; then
            continue
        fi

        # Exclude lines that may contain sensitive information
        if [[ "$trimmed_line" == *'PASSWORD'* || "$trimmed_line" == *'TOKEN'* || "$trimmed_line" == *'SECRET'* ]]; then
            log_message VERBOSE "Processing line $line_number: [REDACTED] Sensitive information omitted."
        else
            log_message VERBOSE "Processing line $line_number: $trimmed_line"
        fi

        # Process variable assignments
        if [[ "$trimmed_line" == *'='* && "$trimmed_line" != *'=='* ]]; then
            process_variable_assignment "$trimmed_line"
        fi

        # Process different types of lines
        if [[ "$trimmed_line" == (#b)(source|.)[[:space:]]* ]]; then
            # Source or dot command
            local rest="${trimmed_line##${match[1]}[[:space:]]}"
            process_sourced_file "$rest" "$file" "$line_number"
        elif [[ "$trimmed_line" == 'if '* ]]; then
            # Handle multi-line if statements
            process_conditional_block "$file" "$line_number" "$line"
        elif [[ "$trimmed_line" == (#b)(eval|eval[[:space:]]*)* ]]; then
            # Eval command (warn but don't process)
            local eval_command="$trimmed_line"
            log_message INFO "Eval command detected: $eval_command (from $file:$line_number)"
            log_message WARNING "Eval commands are not processed for safety reasons. Please check $eval_command manually."
        elif [[ "$trimmed_line" == 'export PATH='* || "$trimmed_line" == 'PATH='* ]]; then
            # PATH modification
            log_message INFO "PATH modification detected: $file, Line: $line_number"
            update_computed_path "$line" "$file" "$line_number"
        fi
    done < "$file"
}

# Function to process variable assignments
process_variable_assignment() {
    local line="$1"
    # Remove 'export' if present
    line="${line#export }"
    # Split variable name and value
    local var_name="${line%%=*}"
    local var_value="${line#*=}"

    # Remove quotes from value
    var_value="${var_value#\"}"
    var_value="${var_value%\"}"
    var_value="${var_value#\'}"
    var_value="${var_value%\'}"

    # Expand variables in value
    var_value=$(expand_variables "$var_value")

    # Update simulated environment
    SIMULATED_ENV["$var_name"]="$var_value"
}

# Function to process a sourced file
process_sourced_file() {
    local sourced_file="$1"
    local source_file="$2"
    local line_number="$3"
    local original_sourced_file="$sourced_file"
    local source_dir="${source_file:h}"

    # Remove any surrounding quotes
    sourced_file="${sourced_file//\"/}"
    sourced_file="${sourced_file//\'/}"

    # Expand variables in the sourced file path
    sourced_file=$(expand_variables "$sourced_file")

    # Resolve the path of the sourced file
    sourced_file=$(resolve_path "$sourced_file" "$source_dir")

    if [[ -z "$sourced_file" ]]; then
        log_message WARNING "Skipping unresolved path: $original_sourced_file from $source_file:$line_number"
        return
    fi

    if [[ ! -f "$sourced_file" ]]; then
        log_message WARNING "Sourced file does not exist or is not accessible: $sourced_file (originally $original_sourced_file from $source_file:$line_number)"
        return
    fi

    log_message INFO "Resolved sourced file: $sourced_file (originally $original_sourced_file from $source_file:$line_number)"
    process_file "$sourced_file"
}

# Function to process conditional blocks
process_conditional_block() {
    local source_file="$1"
    local line_number="$2"
    local line="$3"
    local condition=""
    local command=""
    local in_condition=true
    local nested_if=0

    # Collect condition
    condition="${line#*if }"
    while IFS= read -r next_line || [[ -n "$next_line" ]]; do
        ((line_number++))
        next_line="${next_line#"${next_line%%[![:space:]]*}"}"
        next_line="${next_line%"${next_line##*[![:space:]]}"}"

        if [[ "$next_line" == 'then' ]]; then
            break
        else
            condition+=" $next_line"
        fi
    done

    # Collect commands until 'fi'
    while IFS= read -r next_line || [[ -n "$next_line" ]]; do
        ((line_number++))
        next_line="${next_line#"${next_line%%[![:space:]]*}"}"
        next_line="${next_line%"${next_line##*[![:space:]]}"}"

        if [[ "$next_line" == 'fi' ]]; then
            break
        elif [[ "$next_line" == 'else' ]]; then
            # Skip else part for simplicity
            while IFS= read -r skip_line || [[ -n "$skip_line" ]]; do
                ((line_number++))
                if [[ "$skip_line" == 'fi' ]]; then
                    break
                fi
            done
            break
        else
            command+="$next_line"$'\n'
        fi
    done

    process_conditional_source "$condition" "$command" "$source_file" "$line_number"
}

# Function to process conditional source commands
process_conditional_source() {
    local condition="$1"
    local command="$2"
    local source_file="$3"
    local line_number="$4"

    # Expand variables in condition
    local condition_expanded=$(expand_variables "$condition")

    # Exclude conditions that may contain sensitive information
    if [[ "$condition_expanded" == *'PASSWORD'* || "$condition_expanded" == *'TOKEN'* || "$condition_expanded" == *'SECRET'* ]]; then
        log_message INFO "Evaluating condition in $source_file at line $line_number: [REDACTED]"
    else
        log_message INFO "Evaluating condition in $source_file at line $line_number: $condition_expanded"
    fi

    # Safely evaluate the condition
    if eval "$condition_expanded" 2>/dev/null; then
        log_message INFO "Condition met. Processing commands inside conditional block."

        # Split commands by line
        local IFS=$'\n'
        local commands=($command)
        for cmd in "${commands[@]}"; do
            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
            cmd="${cmd%"${cmd##*[![:space:]]}"}"

            # Exclude sensitive commands
            if [[ "$cmd" == *'PASSWORD'* || "$cmd" == *'TOKEN'* || "$cmd" == *'SECRET'* ]]; then
                log_message VERBOSE "Processing command: [REDACTED] Sensitive information omitted."
                continue
            fi

            log_message VERBOSE "Processing command: $cmd"

            if [[ "$cmd" == (#b)(source|.)[[:space:]]* ]]; then
                # Source or dot command inside conditional
                local rest="${cmd##${match[1]}[[:space:]]}"
                process_sourced_file "$rest" "$source_file" "$line_number"
            elif [[ "$cmd" == 'export PATH='* || "$cmd" == 'PATH='* ]]; then
                # PATH modification inside conditional
                log_message INFO "PATH modification detected inside conditional: $source_file, Line: $line_number"
                update_computed_path "$cmd" "$source_file" "$line_number"
            else
                # Handle other commands if necessary
                log_message VERBOSE "Skipping command inside conditional block: $cmd"
            fi
        done
    else
        if [[ "$condition_expanded" == *'PASSWORD'* || "$condition_expanded" == *'TOKEN'* || "$condition_expanded" == *'SECRET'* ]]; then
            log_message INFO "Condition not met: [REDACTED]"
        else
            log_message INFO "Condition not met: $condition_expanded"
        fi
    fi
}

# Function to update the computed PATH variables
update_computed_path() {
    local line="$1"
    local source_file="$2"
    local line_number="$3"

    # Remove 'export' if present
    line="${line#export }"

    # Check for command substitutions (which we can't safely process)
    if [[ "$line" == *'$('* || "$line" == *'\`'* ]]; then
        log_message WARNING "Cannot process PATH modification with command substitutions: (from $source_file:$line_number)"
        return
    fi

    if [[ "$line" == *'PATH='* ]]; then
        local path_assignment="${line#*PATH=}"
        path_assignment="${path_assignment//\"/}"
        path_assignment="${path_assignment//\'/}"

        # Check if path_assignment is empty
        if [[ -z "$path_assignment" ]]; then
            log_message WARNING "Empty PATH assignment detected. Skipping. (from $source_file:$line_number)"
            return
        fi

        # Update SIMPLE_COMPUTED_PATH (string-based method)
        local new_path="${path_assignment//\$PATH/$SIMPLE_COMPUTED_PATH}"
        SIMPLE_COMPUTED_PATH=$(expand_variables "$new_path")

        # Update COMPUTED_PATH (array-based method)
        if [[ "$path_assignment" == *'$PATH'* ]]; then
            local before="${path_assignment%%\$PATH*}"
            local after="${path_assignment#*\$PATH}"
            before="${before%:}"
            after="${after#:}"

            before=$(expand_variables "$before")
            after=$(expand_variables "$after")

            local new_path_entries=()
            [[ -n "$before" ]] && new_path_entries+=("${(s/:/)before}")
            new_path_entries+=("${COMPUTED_PATH[@]}")
            [[ -n "$after" ]] && new_path_entries+=("${(s/:/)after}")

            COMPUTED_PATH=("${new_path_entries[@]}")
        else
            local expanded_path=$(expand_variables "$path_assignment")
            if [[ -z "$expanded_path" ]]; then
                log_message WARNING "Expanded PATH assignment is empty. Skipping. (from $source_file:$line_number)"
                return
            fi
            COMPUTED_PATH=("${(s/:/)expanded_path}")
        fi

        # Update simulated environment
        SIMULATED_ENV[PATH]="${(j/:/)COMPUTED_PATH}"

        # Process each entry in COMPUTED_PATH
        for entry in "${COMPUTED_PATH[@]}"; do
            if [[ -z "$entry" ]]; then
                continue
            fi

            local sanitized_entry="$entry"
            sanitized_entry="${sanitized_entry#"${sanitized_entry%%[![:space:]]*}"}"
            sanitized_entry="${sanitized_entry%"${sanitized_entry##*[![:space:]]}"}"

            if [[ -z "$sanitized_entry" ]]; then
                continue
            fi

            # Resolve the path to its canonical form
            local resolved_entry=$(resolve_realpath "$sanitized_entry")
            if [[ -z "$resolved_entry" ]]; then
                resolved_entry="$sanitized_entry"
            fi

            local source_info="$source_file:$line_number"

            # Ensure resolved_entry is a valid associative array key
            if [[ -z "$resolved_entry" ]]; then
                log_message WARNING "Invalid PATH entry detected. Skipping."
                continue
            fi

            # Count occurrences of each PATH entry
            ((PATH_ENTRY_COUNTS["$resolved_entry"]++))

            # Record sources for each PATH entry
            if [[ -z "${PATH_ENTRY_SOURCES["$resolved_entry"]}" ]]; then
                PATH_ENTRY_SOURCES["$resolved_entry"]="$source_info"
            else
                local sources=("${(s:,\ :)PATH_ENTRY_SOURCES["$resolved_entry"]}")
                if [[ "${sources[(Ie)$source_info]}" -eq 0 ]]; then
                    PATH_ENTRY_SOURCES["$resolved_entry"]+=", $source_info"
                fi
            fi
        done
    fi
}

# Function to resolve real paths
resolve_realpath() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath -e "$path" 2>/dev/null || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$path" 2>/dev/null || echo "$path"
    else
        # Fallback method using Zsh parameter expansions
        local dir="${path:h}"
        local base="${path:t}"
        if [[ -d "$dir" ]]; then
            echo "$(cd "$dir" && pwd)/$base"
        else
            echo "$path"
        fi
    fi
}

# Function to check for duplicate PATH entries
check_duplicates() {
    local duplicates=false
    local entry
    local resolved_entries=()

    log_message INFO "Checking duplicates in COMPUTED_PATH:"
    for entry in "${(k)PATH_ENTRY_COUNTS}"; do
        # We have already resolved the entries in update_computed_path
        if (( ${resolved_entries[(Ie)$entry]} )); then
            log_message WARNING "Duplicate PATH entry found (after resolving): $entry"
            log_message WARNING "Occurrences (${PATH_ENTRY_COUNTS["$entry"]} times):"
            local sources=("${(s:,\ :)PATH_ENTRY_SOURCES["$entry"]}")
            for src in "${sources[@]}"; do
                log_message WARNING "  - $src"
            done
            duplicates=true
        else
            resolved_entries+=("$entry")
        fi
    done

    [[ "$duplicates" == false ]] && log_message INFO "No duplicate PATH entries found in COMPUTED_PATH."

    log_message INFO "Checking duplicates in SIMPLE_COMPUTED_PATH:"
    local simple_duplicates=false
    local seen=()
    for entry in ${(s/:/)SIMPLE_COMPUTED_PATH}; do
        # Resolve the entry
        local resolved_entry=$(resolve_realpath "$entry")
        if [[ -z "$resolved_entry" ]]; then
            resolved_entry="$entry"
        fi
        if (( ${seen[(Ie)$resolved_entry]} )); then
            log_message WARNING "Duplicate PATH entry found in SIMPLE_COMPUTED_PATH: $resolved_entry"
            simple_duplicates=true
        else
            seen+=("$resolved_entry")
        fi
    done

    [[ "$simple_duplicates" == false ]] && log_message INFO "No duplicate PATH entries found in SIMPLE_COMPUTED_PATH."
}

# Function to display help message
print_help() {
    echo "Usage: $0 [options] [files...]"
    echo
    echo "Options:"
    echo "  -v, --verbose    Enable verbose output"
    echo "  -h, --help       Display this help message"
    echo
    echo "If no files are specified, the script will process default configuration files."
}

# Main function to orchestrate the script's operation
main() {
    log_message VERBOSE "Script started"
    log_message VERBOSE "Starting main function"
    local config_files=("$@")

    # If no files are specified, use default files
    if [[ ${#config_files[@]} -eq 0 ]]; then
        config_files=(
            "$HOME/.zlogin"
            "$HOME/.zshrc"
            "$HOME/.zprofile"
            "$HOME/.zshenv"
            "$HOME/.bashrc"
            "$HOME/.bash_profile"
            "$HOME/.profile"
        )
    fi

    COMPUTED_PATH=("${(s/:/)PATH}")

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            process_file "$file"
            echo
        else
            log_message VERBOSE "File $file does not exist. Skipping."
        fi
    done

    if [[ ${#UNDEFINED_VARIABLES[@]} -gt 0 ]]; then
        local unique_vars=("${(@u)UNDEFINED_VARIABLES}")
        log_message WARNING "The following environment variables were undefined during processing: ${unique_vars[*]}"
    fi

    local computed_path_string="${(j/:/)COMPUTED_PATH}"
    log_message INFO "Actual Path: $PATH"
    log_message INFO "Computed Path (array method): $computed_path_string"
    log_message INFO "Simple Computed Path (string method): $SIMPLE_COMPUTED_PATH"
    echo

    check_duplicates
    log_message VERBOSE "Finished main function"
}

# Parse command-line options
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        -*)
            log_message ERROR "Invalid Option: $1"
            print_help
            exit 1
            ;;
        *)
            # Collect positional arguments (file paths)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

main "$@"
