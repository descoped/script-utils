#!/bin/bash

# test-secrets-sanitizer.sh
# A script to test the secrets-sanitizer.sh script with various inputs and outputs
# This script generates random test data with various types of secrets

# Make sure secrets-sanitizer.sh exists and is executable
if [[ ! -f ./secrets-sanitizer.sh ]]; then
    echo "Error: secrets-sanitizer.sh not found in current directory."
    exit 1
fi

if [[ ! -x ./secrets-sanitizer.sh ]]; then
    chmod +x ./secrets-sanitizer.sh
    echo "Made secrets-sanitizer.sh executable."
fi

# Create test data directory with clear structure
TEST_DIR="./sanitizer_test"
mkdir -p "$TEST_DIR"
mkdir -p "$TEST_DIR/input"
mkdir -p "$TEST_DIR/output"
echo "Created test directory structure: $TEST_DIR"

# Function to generate random strings
random_string() {
    local length=$1
    local chars=$2
    LC_ALL=C tr -dc "$chars" < /dev/urandom | head -c "$length"
}

# Generate AWS credentials
aws_access_key="AKIA$(random_string 16 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')"
aws_secret_key="$(random_string 40 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/+=')"
aws_session_token="$(random_string 260 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/+=')"

# Generate Azure credentials
azure_account_key="$(random_string 88 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/=')"
azure_connection_string="DefaultEndpointsProtocol=https;AccountName=myaccount;AccountKey=${azure_account_key};EndpointSuffix=core.windows.net"
azure_sas_token="sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacupitfx&se=2023-12-31T21:00:00Z&sig=$(random_string 64 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789%+/=')"

# Generate generic API credentials
api_key="$(random_string 32 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')"
auth_token="$(random_string 48 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-')"
jwt_header="$(random_string 15 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-')"
jwt_payload="$(random_string 40 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-')"
jwt_signature="$(random_string 30 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-')"
jwt="eyJ${jwt_header}.${jwt_payload}.${jwt_signature}"

# Generate database credentials
db_password="$(random_string 16 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*')"

# Create plaintext input file
INPUT_PLAINTEXT="$TEST_DIR/input/plaintext_with_secrets.txt"
cat > "$INPUT_PLAINTEXT" << EOF
# AWS Configuration
aws_access_key_id = "$aws_access_key"
aws_secret_access_key = "$aws_secret_key"
aws_session_token = "$aws_session_token"

# Debug output from application
[INFO] Starting application at 2023-11-15 14:32:41
[DEBUG] Environment: Production
[INFO] Connecting to database...
[DEBUG] Connection string: "Server=db.example.com;Database=myapp;User Id=admin;Password=$db_password;"
[INFO] Database connection established

# Azure Configuration
AZURE_STORAGE_CONNECTION_STRING="$azure_connection_string"
AZURE_STORAGE_SAS_TOKEN="$azure_sas_token"

# API Configuration
API_KEY = "$api_key"
AUTH_TOKEN = "$auth_token"

# Authentication header used in requests
Authorization: Bearer $auth_token

# JWT from last authentication
token=$jwt

# Private key (don't share!) - partial example
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKj
MzEfRq6bb5Yps8WF9jkl7mSVGPR4C9OqXVnR3+rRYq8Z1NmH2iDGpP4SnXVOklxz
HEI7JTwRjR0Exxiu6bfCOlqp0xwOSEOF/Q6TDCm4o1jdBD/apgiGgV/xQjKedbi0
[...]
-----END PRIVATE KEY-----

# Log excerpt with sensitive information
[11:42:35] User authenticated successfully
[11:42:36] Processing payment for order #12345
[11:42:37] API response: {"status":"success","customer_id":"cust_1234","charge_id":"ch_5678"}
[11:42:38] Authorization token: $auth_token
[11:42:39] Payment processed successfully

# End of file
EOF

echo "Created plaintext input file: $INPUT_PLAINTEXT"

# Create a JSON input file with secrets
INPUT_JSON="$TEST_DIR/input/json_with_secrets.json"
cat > "$INPUT_JSON" << EOF
{
  "aws": {
    "access_key": "$aws_access_key",
    "secret_key": "$aws_secret_key",
    "region": "us-west-2"
  },
  "azure": {
    "connection_string": "$azure_connection_string",
    "sas_token": "$azure_sas_token"
  },
  "api": {
    "key": "$api_key",
    "endpoint": "https://api.example.com/v1",
    "token": "$auth_token"
  },
  "database": {
    "host": "db.example.com",
    "user": "admin",
    "password": "$db_password",
    "name": "myapp"
  },
  "jwt": "$jwt",
  "debug": false
}
EOF

echo "Created JSON input file: $INPUT_JSON"

# Define output files with consistent naming
OUTPUT_PLAINTEXT="$TEST_DIR/output/plaintext_sanitized.txt"
OUTPUT_JSON="$TEST_DIR/output/json_sanitized.json"
OUTPUT_CLIPBOARD_TO_FILE="$TEST_DIR/output/clipboard_to_file_sanitized.txt"

# Now let's run tests with different variations

echo ""
echo "=== TEST 1: Plaintext File to File ==="
echo "Running: ./secrets-sanitizer.sh -i $INPUT_PLAINTEXT -o $OUTPUT_PLAINTEXT"
./secrets-sanitizer.sh -i "$INPUT_PLAINTEXT" -o "$OUTPUT_PLAINTEXT"
echo "Result file: $OUTPUT_PLAINTEXT"

echo ""
echo "=== TEST 2: JSON File to File ==="
echo "Running: ./secrets-sanitizer.sh -i $INPUT_JSON -o $OUTPUT_JSON"
./secrets-sanitizer.sh -i "$INPUT_JSON" -o "$OUTPUT_JSON"
echo "Result file: $OUTPUT_JSON"

echo ""
echo "=== TEST 3: Plaintext File to Clipboard ==="
echo "Running: ./secrets-sanitizer.sh -i $INPUT_PLAINTEXT"
./secrets-sanitizer.sh -i "$INPUT_PLAINTEXT"
echo "Content is now in clipboard. You can paste it somewhere to verify."

echo ""
echo "=== TEST 4: Clipboard to File ==="
echo "First, copying plaintext content to clipboard..."
cat "$INPUT_PLAINTEXT" | pbcopy
echo "Running: ./secrets-sanitizer.sh -o $OUTPUT_CLIPBOARD_TO_FILE"
./secrets-sanitizer.sh -o "$OUTPUT_CLIPBOARD_TO_FILE"
echo "Result file: $OUTPUT_CLIPBOARD_TO_FILE"

echo ""
echo "=== TEST 5: Clipboard to Clipboard ==="
echo "First, copying JSON content to clipboard..."
cat "$INPUT_JSON" | pbcopy
echo "Running: ./secrets-sanitizer.sh"
./secrets-sanitizer.sh
echo "Sanitized content is now in clipboard. You can paste it somewhere to verify."

echo ""
echo "All tests completed!"
echo ""
echo "Input files:"
echo "  - Plaintext: $INPUT_PLAINTEXT"
echo "  - JSON: $INPUT_JSON"
echo ""
echo "Output files:"
echo "  - Test 1 (Plaintext): $OUTPUT_PLAINTEXT"
echo "  - Test 2 (JSON): $OUTPUT_JSON"
echo "  - Test 4 (Clipboard to File): $OUTPUT_CLIPBOARD_TO_FILE"
echo "  - Test 3 & 5: Results in clipboard"
