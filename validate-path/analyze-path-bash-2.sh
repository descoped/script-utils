#!/usr/bin/env bash

#
# Developed with Claude 3.5 Sonnet, OpenAI 4o and OpenAI 1o-preview
#

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

# Simulated environment variables (using arrays instead of associative arrays)
SIMULATED_ENV_NAMES=()
SIMULATED_ENV_VALUES=()

# PATH entry sources and counts (using arrays instead of associative arrays)
PATH_ENTRIES=()
PATH_ENTRY_SOURCES=()
PATH_ENTRY_COUNTS=()

# Function to add or update a variable in simulated environment
add_to_simulated_env() {
    local var_name="$1"
    local var_value="$2"
    local index
    index=$(get_simulated_env_index "$var_name")
    if [[ -z "$index" ]]; then
        SIMULATED_ENV_NAMES+=("$var_name")
        SIMULATED_ENV_VALUES+=("$var_value")
    else
        SIMULATED_ENV_VALUES[$index]="$var_value"
    fi
}

# Function to get the value of a variable from simulated environment
get_simulated_env() {
    local var_name="$1"
    local index
    index=$(get_simulated_env_index "$var_name")
    if [[ -n "$index" ]]; then
        echo "${SIMULATED_ENV_VALUES[$index]}"
    else
        echo ""
    fi
}

# Function to get the index of a variable in simulated environment arrays
get_simulated_env_index() {
    local var_name="$1"
    local i
    for ((i=0; i<${#SIMULATED_ENV_NAMES[@]}; i++)); do
        if [[ "${SIMULATED_ENV_NAMES[$i]}" == "$var_name" ]]; then
            echo "$i"
            return
        fi
    done
    echo ""
}

# Function to safely expand variables in a string using simulated environment
expand_variables() {
    local input="$1"
    local output="$input"
    local var_pattern='\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}'      # Matches ${VAR}
    local simple_var_pattern='\$([a-zA-Z_][a-zA-Z0-9_]*)'   # Matches $VAR

    # First, handle ${VAR} patterns
    while [[ "$output" =~ $var_pattern ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value
        var_value=$(get_simulated_env "$var_name")

        if [[ -z "$var_value" ]]; then
            UNDEFINED_VARIABLES+=("$var_name")
            log_message WARNING "Environment variable '$var_name' is not set."
            output="${output//\$\{${var_name}\}/}"
        else
            output="${output//\$\{${var_name}\}/$var_value}"
        fi
    done

    # Next, handle $VAR patterns
    while [[ "$output" =~ $simple_var_pattern ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value
        var_value=$(get_simulated_env "$var_name")

        if [[ -z "$var_value" ]]; then
            UNDEFINED_VARIABLES+=("$var_name")
            log_message WARNING "Environment variable '$var_name' is not set."
            output="${output//\$${var_name}/}"
        else
            output="${output//\$${var_name}/$var_value}"
        fi
    done

    # Check for any remaining unhandled parameter expansions
    if [[ "$output" =~ \$\{.*\} ]]; then
        log_message WARNING "Complex parameter expansion detected in: $input. Skipping expansion."
        output="$input"
    fi

    echo "$output"
}

# Function to resolve and normalize file paths
resolve_path() {
    local path="$1"
    local base_dir="$2"

    # Expand tilde to $HOME
    path="${path/#\~/"$(get_simulated_env "HOME")"}"

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
        # Fallback method
        path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    fi

    echo "$path"
}

# Function to resolve real paths
resolve_realpath() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath -e "$path" 2>/dev/null || echo "$path"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$path" 2>/dev/null || echo "$path"
    else
        # Fallback method
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi
}

# Function to add or update a PATH entry
add_or_update_path_entry() {
    local entry="$1"
    local source_info="$2"
    local index
    index=$(get_path_entry_index "$entry")
    if [[ -z "$index" ]]; then
        PATH_ENTRIES+=("$entry")
        PATH_ENTRY_SOURCES+=("$source_info")
        PATH_ENTRY_COUNTS+=(1)
    else
        PATH_ENTRY_COUNTS[$index]=$((PATH_ENTRY_COUNTS[$index] + 1))
        PATH_ENTRY_SOURCES[$index]+=", $source_info"
    fi
}

# Function to get the index of a PATH entry
get_path_entry_index() {
    local entry="$1"
    local i
    for ((i=0; i<${#PATH_ENTRIES[@]}; i++)); do
        if [[ "${PATH_ENTRIES[$i]}" == "$entry" ]]; then
            echo "$i"
            return
        fi
    done
    echo ""
}

# Function to check if output is being piped
is_piped() {
    [[ -t 1 ]] || return 0
    return 1
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
        message="${message//PASSWORD/[REDACTED]}"
        message="${message//TOKEN/[REDACTED]}"
        message="${message//SECRET/[REDACTED]}"
    fi

    if [[ "$VERBOSE" == true ]] || [[ "$level" != "VERBOSE" ]]; then
        echo_color "$level" "$message"
    fi
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

    # Check for complex parameter expansions
    if [[ "$var_value" =~ \$\{.*\} ]]; then
        log_message WARNING "Complex parameter expansion in variable assignment: $line. Skipping variable expansion."
        # Update simulated environment without expanding
        add_to_simulated_env "$var_name" "$var_value"
        return
    fi

    # Expand variables in value
    var_value=$(expand_variables "$var_value")

    # Update simulated environment
    add_to_simulated_env "$var_name" "$var_value"
}

# Function to process a sourced file
process_sourced_file() {
    local sourced_file="$1"
    local source_file="$2"
    local line_number="$3"
    local original_sourced_file="$sourced_file"
    local source_dir="$(dirname "$source_file")"

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
    local condition_expanded
    condition_expanded=$(expand_variables "$condition")

    # Exclude sensitive information in conditions
    local display_condition="$condition_expanded"
    if [[ "$display_condition" == *'PASSWORD'* || "$display_condition" == *'TOKEN'* || "$display_condition" == *'SECRET'* ]]; then
        display_condition="${display_condition//PASSWORD/[REDACTED]}"
        display_condition="${display_condition//TOKEN/[REDACTED]}"
        display_condition="${display_condition//SECRET/[REDACTED]}"
    fi

    log_message INFO "Evaluating condition in $source_file at line $line_number: $display_condition"

    # Safely evaluate the condition using Bash's built-in test
    if [[ -n "$condition_expanded" ]] && bash -c "if $condition_expanded; then exit 0; else exit 1; fi" 2>/dev/null; then
        log_message INFO "Condition met. Processing commands inside conditional block."

        # Split commands by line
        local IFS=$'\n'
        local commands=($command)
        for cmd in "${commands[@]}"; do
            cmd="${cmd#"${cmd%%[![:space:]]*}"}"
            cmd="${cmd%"${cmd##*[![:space:]]}"}"

            # Exclude sensitive commands
            local display_cmd="$cmd"
            if [[ "$display_cmd" == *'PASSWORD'* || "$display_cmd" == *'TOKEN'* || "$display_cmd" == *'SECRET'* ]]; then
                display_cmd="${display_cmd//PASSWORD/[REDACTED]}"
                display_cmd="${display_cmd//TOKEN/[REDACTED]}"
                display_cmd="${display_cmd//SECRET/[REDACTED]}"
            fi

            log_message VERBOSE "Processing command: $display_cmd"

            if [[ "$cmd" =~ ^(source|\.)[[:space:]]+ ]]; then
                # Source or dot command inside conditional
                local rest="${cmd#*(source|.)[[:space:]]}"
                process_sourced_file "$rest" "$source_file" "$line_number"
            elif [[ "$cmd" =~ ^(export )?PATH= ]]; then
                # PATH modification inside conditional
                log_message INFO "PATH modification detected inside conditional: $source_file, Line: $line_number"
                update_computed_path "$cmd" "$source_file" "$line_number"
            else
                # Handle variable assignments
                if [[ "$cmd" =~ ^(export )?[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
                    process_variable_assignment "$cmd"
                else
                    # Log other commands
                    log_message VERBOSE "Skipping command inside conditional block: $display_cmd"
                fi
            fi
        done
    else
        log_message INFO "Condition not met: $display_condition"
    fi  # Added missing fi
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
            IFS=':' read -r -a before_entries <<< "$before"
            IFS=':' read -r -a after_entries <<< "$after"

            [[ -n "$before" ]] && new_path_entries+=("${before_entries[@]}")
            new_path_entries+=("${COMPUTED_PATH[@]}")
            [[ -n "$after" ]] && new_path_entries+=("${after_entries[@]}")

            COMPUTED_PATH=("${new_path_entries[@]}")
        else
            local expanded_path=$(expand_variables "$path_assignment")
            if [[ -z "$expanded_path" ]]; then
                log_message WARNING "Expanded PATH assignment is empty. Skipping. (from $source_file:$line_number)"
                return
            fi
            IFS=':' read -r -a COMPUTED_PATH <<< "$expanded_path"
        fi

        # Update simulated environment
        add_to_simulated_env "PATH" "${COMPUTED_PATH[*]}"

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
            local resolved_entry
            resolved_entry=$(resolve_realpath "$sanitized_entry")
            if [[ -z "$resolved_entry" ]]; then
                resolved_entry="$sanitized_entry"
            fi

            local source_info="$source_file:$line_number"

            # Record the PATH entry
            add_or_update_path_entry "$resolved_entry" "$source_info"
        done
    fi
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

    # Read the file content
    local file_content
    file_content=$(cat "$file")

    # Process the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))

        # Trim leading and trailing whitespace
        local trimmed_line="${line#"${line%%[![:space:]]*}"}"
        trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"

        # Exclude lines that may contain sensitive information
        local display_line="$trimmed_line"
        if [[ "$display_line" == *'PASSWORD'* || "$display_line" == *'TOKEN'* || "$display_line" == *'SECRET'* ]]; then
            display_line="${display_line//PASSWORD/[REDACTED]}"
            display_line="${display_line//TOKEN/[REDACTED]}"
            display_line="${display_line//SECRET/[REDACTED]}"
        fi

        # Log the line being processed
        log_message VERBOSE "Processing line $line_number: $display_line"

        # Skip empty lines
        if [[ -z "$trimmed_line" ]]; then
            continue
        fi

        # Process variable assignments
        if [[ "$trimmed_line" =~ ^(export )?[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
            process_variable_assignment "$trimmed_line"
        fi

        # Process different types of lines
        if [[ "$trimmed_line" =~ ^(source|\.)[[:space:]]+ ]]; then
            # Source or dot command
            local rest="${trimmed_line#*(source|.)[[:space:]]}"
            process_sourced_file "$rest" "$file" "$line_number"
        elif [[ "$trimmed_line" =~ ^if[[:space:]]+.* ]]; then
            # Handle multi-line if statements
            process_conditional_block "$file" "$line_number" "$trimmed_line"
        elif [[ "$trimmed_line" =~ ^eval[[:space:]]+.* ]]; then
            # Eval command (warn but don't process)
            local eval_command="$trimmed_line"
            log_message INFO "Eval command detected: $eval_command (from $file:$line_number)"
            log_message WARNING "Eval commands are not processed for safety reasons. Please check $eval_command manually."
        elif [[ "$trimmed_line" =~ ^(export )?PATH= ]]; then
            # PATH modification
            log_message INFO "PATH modification detected: $file, Line: $line_number"
            update_computed_path "$trimmed_line" "$file" "$line_number"
        fi
    done <<< "$file_content"
}

# Function to check for duplicate PATH entries
check_duplicates() {
    local duplicates=false
    local resolved_entries=()

    log_message INFO "Checking duplicates in COMPUTED_PATH:"
    for ((i=0; i<${#PATH_ENTRIES[@]}; i++)); do
        local entry="${PATH_ENTRIES[$i]}"
        if [[ " ${resolved_entries[*]} " == *" $entry "* ]]; then
            log_message WARNING "Duplicate PATH entry found (after resolving): $entry"
            log_message WARNING "Occurrences (${PATH_ENTRY_COUNTS[$i]} times):"
            local sources="${PATH_ENTRY_SOURCES[$i]}"
            log_message WARNING "  - $sources"
            duplicates=true
        else
            resolved_entries+=("$entry")
        fi
    done

    [[ "$duplicates" == false ]] && log_message INFO "No duplicate PATH entries found in COMPUTED_PATH."

    log_message INFO "Checking duplicates in SIMPLE_COMPUTED_PATH:"
    local simple_duplicates=false
    local seen=()
    IFS=':' read -r -a path_entries <<< "$SIMPLE_COMPUTED_PATH"
    for entry in "${path_entries[@]}"; do
        # Resolve the entry
        local resolved_entry
        resolved_entry=$(resolve_realpath "$entry")
        if [[ -z "$resolved_entry" ]]; then
            resolved_entry="$entry"
        fi
        if [[ " ${seen[*]} " == *" $resolved_entry "* ]]; then
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
            "$HOME/.bash_profile"
            "$HOME/.bashrc"
            "$HOME/.profile"
            "$HOME/.bash_login"
            "$HOME/.zshrc"
            "$HOME/.zprofile"
            "$HOME/.zshenv"
            "$HOME/.zlogin"
        )
    fi

    IFS=':' read -r -a COMPUTED_PATH <<< "$PATH"

    # Initialize essential environment variables
    add_to_simulated_env "PATH" "$PATH"
    add_to_simulated_env "HOME" "$HOME"

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            process_file "$file"
            echo
        else
            log_message VERBOSE "File $file does not exist. Skipping."
        fi
    done

    if [[ ${#UNDEFINED_VARIABLES[@]} -gt 0 ]]; then
        local unique_vars=($(printf "%s\n" "${UNDEFINED_VARIABLES[@]}" | sort -u))
        log_message WARNING "The following environment variables were undefined during processing: ${unique_vars[*]}"
    fi

    log_message INFO "Actual Path: $PATH"
    log_message INFO "Computed Path (array method): ${COMPUTED_PATH[*]}"
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
