#!/bin/bash

# test-secret-sanitizer.sh
# A script to test the secret-sanitizer.sh script with various inputs and outputs
# This script generates random test data with various types of secrets

# Make sure secret-sanitizer.sh exists and is executable
if [[ ! -f ./secret-sanitizer.sh ]]; then
    echo "Error: secret-sanitizer.sh not found in current directory."
    exit 1
fi

if [[ ! -x ./secret-sanitizer.sh ]]; then
    chmod +x ./secret-sanitizer.sh
    echo "Made secret-sanitizer.sh executable."
fi

# Create test data directory
TEST_DIR="./sanitizer_test"
mkdir -p "$TEST_DIR"
echo "Created test directory: $TEST_DIR"

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

# Create test data file
TEST_FILE="$TEST_DIR/sample_with_secrets.txt"
cat > "$TEST_FILE" << EOF
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

echo "Created test file with sample secrets: $TEST_FILE"

# Create a JSON file with secrets
TEST_JSON="$TEST_DIR/config.json"
cat > "$TEST_JSON" << EOF
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

echo "Created test JSON file with sample secrets: $TEST_JSON"

# Now let's run tests with different variations

echo ""
echo "=== TEST 1: File to File ==="
echo "Running: ./secret-sanitizer.sh -i $TEST_FILE -o $TEST_DIR/file_to_file.txt"
./secret-sanitizer.sh -i "$TEST_FILE" -o "$TEST_DIR/file_to_file.txt"
echo "Result file: $TEST_DIR/file_to_file.txt"

echo ""
echo "=== TEST 2: JSON File to File ==="
echo "Running: ./secret-sanitizer.sh -i $TEST_JSON -o $TEST_DIR/json_to_file.txt"
./secret-sanitizer.sh -i "$TEST_JSON" -o "$TEST_DIR/json_to_file.txt"
echo "Result file: $TEST_DIR/json_to_file.txt"

echo ""
echo "=== TEST 3: File to Clipboard ==="
echo "Running: ./secret-sanitizer.sh -i $TEST_FILE"
./secret-sanitizer.sh -i "$TEST_FILE"
echo "Content is now in clipboard. You can paste it somewhere to verify."

echo ""
echo "=== TEST 4: Clipboard to File ==="
echo "First, copying original content to clipboard..."
cat "$TEST_FILE" | pbcopy
echo "Running: ./secret-sanitizer.sh -o $TEST_DIR/clipboard_to_file.txt"
./secret-sanitizer.sh -o "$TEST_DIR/clipboard_to_file.txt"
echo "Result file: $TEST_DIR/clipboard_to_file.txt"

echo ""
echo "=== TEST 5: Clipboard to Clipboard ==="
echo "First, copying original content to clipboard..."
cat "$TEST_JSON" | pbcopy
echo "Running: ./secret-sanitizer.sh"
./secret-sanitizer.sh
echo "Sanitized content is now in clipboard. You can paste it somewhere to verify."

echo ""
echo "All tests completed!"
echo "Check the $TEST_DIR directory for output files."
