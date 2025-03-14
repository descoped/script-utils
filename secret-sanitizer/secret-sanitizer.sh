#!/bin/bash

# secret-sanitizer.sh
# A simple script to obfuscate secrets in text for safe sharing
# Specifically designed for macOS compatibility
#
# Features:
# - Read from clipboard or file
# - Write to clipboard or file
# - Detects and obfuscates common secrets/API keys

# Display help information
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -i, --input FILE       Read from FILE instead of clipboard"
    echo "  -o, --output FILE      Write to FILE instead of clipboard"
    echo "  -c, --clipboard        Read from clipboard (default if no input file)"
    echo "  -r, --replace          Replace clipboard content (default if no output file)"
    echo "  -v, --verbose          Show more detailed information"
    echo "  -h, --help             Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0                        # Read from clipboard, write back to clipboard"
    echo "  $0 -i debug.log           # Read from debug.log, write to clipboard"
    echo "  $0 -o sanitized.txt       # Read from clipboard, write to sanitized.txt"
    echo "  $0 -i input.txt -o output.txt  # Read from input.txt, write to output.txt"
    exit 0
}

# Default options
INPUT_FILE=""
OUTPUT_FILE=""
READ_CLIPBOARD=false
WRITE_CLIPBOARD=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--clipboard)
            READ_CLIPBOARD=true
            shift
            ;;
        -r|--replace)
            WRITE_CLIPBOARD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Set defaults if no options provided
if [[ -z "$INPUT_FILE" && "$READ_CLIPBOARD" = false ]]; then
    READ_CLIPBOARD=true
fi

if [[ -z "$OUTPUT_FILE" && "$WRITE_CLIPBOARD" = false ]]; then
    WRITE_CLIPBOARD=true
fi

# Create a temporary file for processing
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE" "$TEMP_FILE.tmp" 2>/dev/null' EXIT

# Get input content
if [[ -n "$INPUT_FILE" ]]; then
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "Error: Input file '$INPUT_FILE' not found."
        exit 1
    fi
    cat "$INPUT_FILE" > "$TEMP_FILE"
    echo "Reading from file: $INPUT_FILE"
else
    # Read from clipboard using pbpaste (macOS)
    pbpaste > "$TEMP_FILE"
    echo "Reading from clipboard"
fi

echo "Scanning for secrets..."

# Initialize counter for secrets found
SECRETS_FOUND=0
AWS_SECRETS=0
AZURE_SECRETS=0
API_SECRETS=0
JWT_SECRETS=0
PASSWORD_SECRETS=0
PRIVATE_KEY_SECRETS=0
GITHUB_SECRETS=0
GOOGLE_SECRETS=0

# Function for simple replacements with sed
do_replacement() {
    local pattern="$1"
    local replacement="$2"
    local file="$3"
    local count_var="$4"
    local sed_script="/$(echo "$pattern" | sed -e 's/\//\\\//g')/s//$(echo "$replacement" | sed -e 's/\//\\\//g')/g"

    # Check if pattern exists in the file
    if grep -q "$pattern" "$file"; then
        # Count occurrences
        local matches=$(grep -c "$pattern" "$file" || echo 0)
        SECRETS_FOUND=$((SECRETS_FOUND + matches))
        eval "$count_var=$((${!count_var} + matches))"

        # Perform replacement
        sed -i '' "$sed_script" "$file"
    fi
}

# Function to process entire file with awk for more complex matches
process_with_awk() {
    local input_file="$1"
    local output_file="$2"
    local type="$3"
    local count_var="$4"
    local pattern="$5"
    local replacement="$6"

    awk -v pattern="$pattern" -v replacement="$replacement" -v count_var="$count_var" '
    {
        if ($0 ~ pattern) {
            count++;
            gsub(pattern, replacement);
        }
        print;
    }
    END {
        if (count > 0) {
            print count " secrets of type " count_var " found" > "/dev/stderr";
        }
    }
    ' "$input_file" > "$output_file"

    # Get the count from awk
    local matches=$(awk -v pattern="$pattern" 'BEGIN{count=0} $0 ~ pattern {count++} END{print count}' "$input_file")
    if [ "$matches" -gt 0 ]; then
        SECRETS_FOUND=$((SECRETS_FOUND + matches))
        eval "$count_var=$((${!count_var} + matches))"
    fi

    # Replace input with output
    mv "$output_file" "$input_file"
}

# 1. AWS Access Keys (AKIA...)
do_replacement "AKIA[A-Z0-9]\{16\}" "[AWS-KEY-REDACTED]" "$TEMP_FILE" "AWS_SECRETS"

# General catch-all for timestamped log entries with key-value pairs
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Timestamped Logs" "API_SECRETS" "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9:.]\+Z [A-Z_]*(SECRET|KEY|TOKEN|AUTH|CRED|PASS|SIGN|IDENTITY|MSI)[A-Z_]*=[A-Za-z0-9/+._=-]*" "&=[SENSITIVE-VALUE-REDACTED]"

# Additional catch-all for specific cloud provider API keys and secrets
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Cloud API Keys" "API_SECRETS" "AZURE.*_KEY_[0-9]=[A-Za-z0-9/+._=-]*" "&=[API-KEY-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Cloud API Keys Quoted" "API_SECRETS" "AZURE.*_KEY_[0-9]=\"[^\"]*\"" "&=\"[API-KEY-REDACTED]\""

# 2. AWS Secret Keys - Update pattern to catch more variations
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "AWS Secret Key" "AWS_SECRETS" "[Aa][Ww][Ss]_[Ss][Ee][Cc][Rr][Ee][Tt]_[Aa][Cc][Cc][Ee][Ss][Ss]_[Kk][Ee][Yy][ ]*=[ ]*[\"']?[A-Za-z0-9+/=]\{20,\}[\"']?" "aws_secret_access_key = \"[AWS-SECRET-REDACTED]\""
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "AWS Secret Key in JSON" "AWS_SECRETS" "\"secret_key\"[ ]*:[ ]*\"[A-Za-z0-9+/=]\{20,\}\"" "\"secret_key\": \"[AWS-SECRET-REDACTED]\""

# 3. AWS Session tokens - relatively long strings, often in base64
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "AWS Session Token" "AWS_SECRETS" "aws_session_token[ ]*=[ ]*[\"'][A-Za-z0-9+/=]\{100,\}[\"']" "aws_session_token = \"[AWS-SESSION-TOKEN-REDACTED]\""

# 4. Azure Connection String - focus on the AccountKey part
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Azure Connection String" "AZURE_SECRETS" "AccountKey=[A-Za-z0-9+/=]\{50,\}" "AccountKey=[AZURE-KEY-REDACTED]"

# 5. Azure SAS Tokens - improve the pattern to avoid double redaction
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Azure SAS Token" "AZURE_SECRETS" "sig=[A-Za-z0-9%+/=]\{30,\}" "sig=[AZURE-SAS-SIGNATURE-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "SAS Token Env Var" "AZURE_SECRETS" "AZURE_STORAGE_SAS_TOKEN=\"[^\"]*\"" "AZURE_STORAGE_SAS_TOKEN=\"[SAS-TOKEN-REDACTED]\""

# Environment variables containing sensitive keywords - more comprehensive patterns
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Secret Env Vars" "API_SECRETS" "[A-Z_]*(SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Z_]*=[A-Za-z0-9/+._=-]*" "&=[SECRET-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Secret Env Vars Quoted" "API_SECRETS" "[A-Z_]*(SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Z_]*=\"[^\"]*\"" "&=\"[SECRET-REDACTED]\""

# Fix ordering - process specific patterns first, then generic ones to prevent double redaction
# This section moved here to ensure it runs after specific patterns

# Special handling for API keys (common in Azure and cloud services)
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "API Keys" "API_SECRETS" "[A-Z_]*API_KEY[A-Z0-9_]*=[A-Za-z0-9/+._=-]*" "&=[API-KEY-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Azure API Keys" "API_SECRETS" "(AZURE|APPSETTING).*API_KEY.*=[A-Za-z0-9/+._=-]*" "&=[API-KEY-REDACTED]"

# 6. Generic API Keys - various formats (updated to handle more patterns)
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "API Key" "API_SECRETS" "API_KEY[ ]*=[ ]*[\"']?[A-Za-z0-9]\{20,\}[\"']?" "API_KEY = \"[API-KEY-REDACTED]\""
# Additional API key pattern for common formats without API_KEY prefix
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Generic API Key" "API_SECRETS" "\"key\"[ ]*:[ ]*\"[A-Za-z0-9]\{20,\}\"" "\"key\": \"[API-KEY-REDACTED]\""

# 7. Generic Auth Tokens - Updated to handle tokens with periods and without quotes
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Auth Token" "API_SECRETS" "AUTH_TOKEN[ ]*=[ ]*[\"']?[A-Za-z0-9._-]\{10,\}[\"']?" "AUTH_TOKEN = \"[AUTH-TOKEN-REDACTED]\""

# Additional patterns for token formats seen in the wild
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Generic Long Token" "API_SECRETS" "[A-Za-z0-9]\{20,\}[a-zA-Z0-9]\{10,\}" "[TOKEN-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Auth Token in Text" "API_SECRETS" "token: [A-Za-z0-9._-]\{10,\}" "token: [AUTH-TOKEN-REDACTED]"

# Additional patterns for identity tokens and signing keys
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Identity Tokens" "API_SECRETS" "(IDENTITY_HEADER|MSI_SECRET)[ ]*=[ ]*[A-Za-z0-9_-]\{10,\}" "&=[IDENTITY-TOKEN-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Signing Keys" "API_SECRETS" "[A-Za-z0-9_]*(SIGNING|ENCRYPTION)_KEY[ ]*=[ ]*[A-Za-z0-9]\{32,\}" "&=[SIGNING-KEY-REDACTED]"

# 8. Generic tokens pattern - handles tokens with dot patterns but avoids non-secret text
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Generic Token" "API_SECRETS" "\\b\\.[A-Za-z0-9_-]\{10,\}\\.[A-Za-z0-9_-]\{10,\}\\b" "[TOKEN-REDACTED]"

# 9. Bearer Tokens
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Bearer Token" "API_SECRETS" "Bearer[ ]+[A-Za-z0-9._-]\{10,\}" "Bearer [BEARER-TOKEN-REDACTED]"

# 10. Authorization tokens outside of typical patterns
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Authorization Token" "API_SECRETS" "Authorization token: [A-Za-z0-9._-]\{10,\}" "Authorization token: [AUTH-TOKEN-REDACTED]"

# 11. JWT Tokens - typically three base64 sections separated by dots
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "JWT Token" "JWT_SECRETS" "eyJ[A-Za-z0-9_-]\{10,\}\\.[A-Za-z0-9_-]\{10,\}\\.[A-Za-z0-9_-]\{10,\}" "[JWT-TOKEN-REDACTED]"

# 12. Database passwords in connection strings - prevent double redaction
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Database Password" "PASSWORD_SECRETS" "Password=[^;\"']+;" "Password=[DB-PASSWORD-REDACTED];"

# 13. Generic passwords - including JSON format and environment variables
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Password" "PASSWORD_SECRETS" "password[ ]*=[ ]*\"[^\"]*\"" "password = \"[PASSWORD-REDACTED]\""
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "JSON Password" "PASSWORD_SECRETS" "\"password\"[ ]*:[ ]*\"[^\"]*\"" "\"password\": \"[PASSWORD-REDACTED]\""
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Password Env Var" "PASSWORD_SECRETS" "[A-Za-z0-9_]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_]*=[A-Za-z0-9/+._=-]*" "&=[PASSWORD-REDACTED]"
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Password Env Var Quoted" "PASSWORD_SECRETS" "[A-Za-z0-9_]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_]*=\"[^\"]*\"" "&=\"[PASSWORD-REDACTED]\""

# 14. GitHub tokens
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "GitHub Token" "GITHUB_SECRETS" "ghp_[A-Za-z0-9]\{36\}" "[GITHUB-TOKEN-REDACTED]"

# 15. Google API Keys
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Google API Key" "GOOGLE_SECRETS" "AIza[A-Za-z0-9_-]\{35\}" "[GOOGLE-API-KEY-REDACTED]"

# 16. Google OAuth Client IDs
process_with_awk "$TEMP_FILE" "$TEMP_FILE.tmp" "Google OAuth Client" "GOOGLE_SECRETS" "[0-9]\{12\}-[A-Za-z0-9_]\{32\}\.apps\.googleusercontent\.com" "[GOOGLE-OAUTH-CLIENT-REDACTED]"

# 17. Private keys - handle with awk for multi-line replacement
if grep -q "BEGIN.*PRIVATE KEY" "$TEMP_FILE"; then
    awk '
    /BEGIN.*PRIVATE KEY/ {
        print;
        print "[PRIVATE-KEY-CONTENT-REDACTED]";
        private_key_count++;
        SECRETS_FOUND++;
        in_key = 1;
        next;
    }
    /END.*PRIVATE KEY/ {
        in_key = 0;
        print;
        next;
    }
    in_key { next; }
    { print; }
    ' "$TEMP_FILE" > "$TEMP_FILE.tmp"

    # Count how many private keys were found
    private_key_count=$(grep -c "BEGIN.*PRIVATE KEY" "$TEMP_FILE" || echo 0)
    SECRETS_FOUND=$((SECRETS_FOUND + private_key_count))
    PRIVATE_KEY_SECRETS=$((PRIVATE_KEY_SECRETS + private_key_count))

    mv "$TEMP_FILE.tmp" "$TEMP_FILE"
fi

# Output the results
if [[ -n "$OUTPUT_FILE" ]]; then
    cat "$TEMP_FILE" > "$OUTPUT_FILE"
    echo "Sanitized content written to: $OUTPUT_FILE"
fi

if [[ "$WRITE_CLIPBOARD" = true ]]; then
    cat "$TEMP_FILE" | pbcopy
    echo "Sanitized content copied to clipboard"
fi

# Report on secrets found
echo "Found $SECRETS_FOUND potential secrets"

if [[ "$VERBOSE" = true || $SECRETS_FOUND -gt 0 ]]; then
    echo "Secret types detected:"
    [ $AWS_SECRETS -gt 0 ] && echo "  - AWS Credentials: $AWS_SECRETS"
    [ $AZURE_SECRETS -gt 0 ] && echo "  - Azure Credentials: $AZURE_SECRETS"
    [ $API_SECRETS -gt 0 ] && echo "  - API Keys/Tokens: $API_SECRETS"
    [ $JWT_SECRETS -gt 0 ] && echo "  - JWT Tokens: $JWT_SECRETS"
    [ $PASSWORD_SECRETS -gt 0 ] && echo "  - Passwords: $PASSWORD_SECRETS"
    [ $PRIVATE_KEY_SECRETS -gt 0 ] && echo "  - Private Keys: $PRIVATE_KEY_SECRETS"
    [ $GITHUB_SECRETS -gt 0 ] && echo "  - GitHub Tokens: $GITHUB_SECRETS"
    [ $GOOGLE_SECRETS -gt 0 ] && echo "  - Google Credentials: $GOOGLE_SECRETS"
fi

exit 0
