#!/usr/bin/env python3
"""
Secret Sanitizer - Identify and redact secrets in text content
"""
import argparse
import json
import re
import sys
from typing import Dict, Tuple

# Secret patterns with their redaction markers
SECRET_PATTERNS = [
    # Process quoted values first
    # 1. API Keys (quoted)
    (r'([A-Za-z0-9_-]*(?:API[_-]KEY|APIKEY)[A-Za-z0-9_-]*)="([^"]*)"', r'\1="[API-KEY]"'),
    (r'([A-Za-z0-9_-]*(?:API[_-]KEY|APIKEY)[A-Za-z0-9_-]*)=\'([^\']*)\'', r'\1=\'[API-KEY]\''),

    # 2. Passwords (quoted)
    (r'([A-Za-z0-9_-]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_-]*)="([^"]*)"', r'\1="[PASSWORD]"'),
    (r'([A-Za-z0-9_-]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_-]*)=\'([^\']*)\'', r'\1=\'[PASSWORD]\''),

    # 3. Generic secrets (quoted)
    (r'([A-Za-z0-9_-]*(?:SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Za-z0-9_-]*)="([^"]*)"', r'\1="[SECRET]"'),
    (
        r'([A-Za-z0-9_-]*(?:SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Za-z0-9_-]*)=\'([^\']*)\'',
        r'\1=\'[SECRET]\''),

    # 4. AWS specific
    (r'AKIA[A-Z0-9]{16}', '[AWS-KEY]'),
    (r'aws_secret_access_key\s*=\s*["\']?([A-Za-z0-9+/=]{20,})["\']?', r'aws_secret_access_key = "[AWS-SECRET]"'),
    (r'"secret_key"\s*:\s*"([A-Za-z0-9+/=]{20,})"', r'"secret_key": "[AWS-SECRET]"'),
    (r'aws_session_token\s*=\s*["\']([A-Za-z0-9+/=]{100,})["\']', r'aws_session_token = "[AWS-SESSION-TOKEN]"'),

    # 5. Azure specific
    (r'AccountKey=([A-Za-z0-9+/=]{50,})', r'AccountKey=[AZURE-KEY]'),
    (r'sig=([A-Za-z0-9%+/=]{30,})', r'sig=[AZURE-SAS]'),
    (r'AZURE_STORAGE_SAS_TOKEN="([^"]*)"', r'AZURE_STORAGE_SAS_TOKEN="[AZURE-SAS]"'),
    (r'AZURE_OPENAI_API_KEY=([^\n\r]*)', r'AZURE_OPENAI_API_KEY=[API-KEY]'),

    # 6. API Keys (unquoted) - requires careful ordering
    (r'(AZURE_API_KEY(?:_\d+)?)=([^\n\r]*)', r'\1=[API-KEY]'),
    (r'([A-Za-z0-9_-]*(?:API[_-]KEY|APIKEY)[A-Za-z0-9_-]*)=([^\n\r]*)', r'\1=[API-KEY]'),

    # 7. JWT and other tokens
    (r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', '[JWT-TOKEN]'),
    (r'AUTH_TOKEN\s*=\s*["\']?([A-Za-z0-9._-]{10,})["\']?', r'AUTH_TOKEN = "[AUTH-TOKEN]"'),
    (r'AUTH-TOKEN\s*=\s*["\']?([A-Za-z0-9._-]{10,})["\']?', r'AUTH-TOKEN = "[AUTH-TOKEN]"'),
    (r'Authorization token: ([A-Za-z0-9._-]{10,})', r'Authorization token: [AUTH-TOKEN]'),
    (r'Bearer\s+([A-Za-z0-9._-]{10,})', r'Bearer [BEARER-TOKEN]'),
    (r'Authorization: Bearer\s+([A-Za-z0-9._-]{10,})', r'Authorization: Bearer [BEARER-TOKEN]'),

    # 8. Passwords (unquoted)
    (r'([A-Za-z0-9_-]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_-]*)=([^\n\r]*)', r'\1=[PASSWORD]'),

    # 9. GitHub tokens
    (r'ghp_[A-Za-z0-9]{36}', '[GITHUB-TOKEN]'),
    (r'github_pat_[A-Za-z0-9_]{22}_[A-Za-z0-9]{59}', '[GITHUB-PAT]'),

    # 10. Google
    (r'AIza[A-Za-z0-9_-]{35}', '[GOOGLE-API-KEY]'),
    (r'[0-9]{12}-[A-Za-z0-9_]{32}\.apps\.googleusercontent\.com', '[GOOGLE-OAUTH]'),

    # 11. Authentication usernames/credentials
    (r'AUTH_USERNAME=([^\n\r]*)', r'AUTH_USERNAME=[USERNAME]'),

    # 12. Generic secrets (unquoted) - should be last to avoid double-matching
    (r'([A-Za-z0-9_-]*(?:SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Za-z0-9_-]*)=([^\n\r]*)',
     r'\1=[SECRET]'),
]


# Handle multi-line patterns separately
def redact_private_keys(content: str) -> Tuple[str, int]:
    """Redact private key contents from PEM files."""
    count = 0
    in_key = False
    redacted_lines = []

    for line in content.splitlines():
        if "BEGIN PRIVATE KEY" in line or "BEGIN RSA PRIVATE KEY" in line:
            in_key = True
            redacted_lines.append(line)
            redacted_lines.append("[PRIVATE-KEY]")
            count += 1
        elif "END PRIVATE KEY" in line or "END RSA PRIVATE KEY" in line:
            in_key = False
            redacted_lines.append(line)
        elif in_key:
            # Skip lines in-between private key markers
            continue
        else:
            redacted_lines.append(line)

    return '\n'.join(redacted_lines), count


def process_json_content(content: str) -> Tuple[str, int]:
    """Special processing for JSON content to handle structured data."""
    # Check if it looks like JSON
    if not (content.strip().startswith('{') and content.strip().endswith('}')):
        return content, 0

    try:
        # Try to parse as JSON
        data = json.loads(content)
        count = 0

        # Process the JSON recursively
        def process_json_obj(obj):
            nonlocal count
            if isinstance(obj, dict):
                for key, value in list(obj.items()):
                    # Check if key indicates a secret
                    is_secret_key = any(word in key.lower() for word in
                                        ['secret', 'key', 'token', 'password', 'auth', 'credential'])

                    if is_secret_key and isinstance(value, str) and len(value) >= 10:
                        # Redact the value
                        marker_type = 'API-KEY'
                        if 'password' in key.lower():
                            marker_type = 'PASSWORD'
                        elif 'secret' in key.lower():
                            marker_type = 'SECRET'
                        elif 'token' in key.lower():
                            marker_type = 'TOKEN'
                        elif 'auth' in key.lower():
                            marker_type = 'AUTH'

                        obj[key] = f"[{marker_type}]"
                        count += 1
                    elif isinstance(value, (dict, list)):
                        # Process nested objects
                        process_json_obj(value)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    if isinstance(item, (dict, list)):
                        process_json_obj(item)

        # Process the entire JSON object
        process_json_obj(data)

        # Convert back to string with pretty formatting
        return json.dumps(data, indent=2), count
    except json.JSONDecodeError:
        # Not valid JSON, return unchanged
        return content, 0


def redact_secrets(content: str) -> Tuple[str, Dict[str, int]]:
    """Redact secrets from text content while preserving line structure."""
    # Initialize counters
    stats = {
        'AWS': 0,
        'Azure': 0,
        'API': 0,
        'JWT': 0,
        'Password': 0,
        'Private': 0,
        'GitHub': 0,
        'Google': 0,
        'Generic': 0
    }

    # First, apply special processing for private keys
    content, private_key_count = redact_private_keys(content)
    stats['Private'] = private_key_count

    # Try to process as JSON
    json_content, json_count = process_json_content(content)
    if json_count > 0:
        content = json_content
        stats['API'] += json_count

    # Process line by line to maintain structure
    lines = content.splitlines(True)  # Keep line endings
    processed_lines = []

    for line in lines:
        current_line = line

        # Apply patterns to each line
        for pattern, replacement in SECRET_PATTERNS:
            matches = list(re.finditer(pattern, current_line))

            # Process matches in reverse to avoid position shifts
            for match in reversed(matches):
                start, end = match.span()
                match_text = match.group(0)

                # Apply the pattern
                new_text = re.sub(pattern, replacement, match_text)
                current_line = current_line[:start] + new_text + current_line[end:]

                # Update stats
                if '[AWS-' in replacement:
                    stats['AWS'] += 1
                elif '[AZURE-' in replacement:
                    stats['Azure'] += 1
                elif '[API-KEY]' in replacement:
                    stats['API'] += 1
                elif '[JWT-TOKEN]' in replacement:
                    stats['JWT'] += 1
                elif '[PASSWORD]' in replacement:
                    stats['Password'] += 1
                elif '[GITHUB-' in replacement:
                    stats['GitHub'] += 1
                elif '[GOOGLE-' in replacement:
                    stats['Google'] += 1
                elif '[USERNAME]' in replacement:
                    stats['Generic'] += 1  # Count usernames in Generic
                else:
                    stats['Generic'] += 1

        processed_lines.append(current_line)

    return ''.join(processed_lines), stats


def main():
    parser = argparse.ArgumentParser(description='Sanitize secrets in text content')
    parser.add_argument('-i', '--input', help='Input file (defaults to stdin)')
    parser.add_argument('-o', '--output', help='Output file (defaults to stdout)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Show detailed information')
    args = parser.parse_args()

    # Get input content
    if args.input:
        try:
            with open(args.input, 'r', encoding='utf-8') as f:
                content = f.read()
            print(f"Reading from file: {args.input}")
        except FileNotFoundError:
            print(f"Error: Input file '{args.input}' not found.")
            sys.exit(1)
    else:
        # Read from stdin
        content = sys.stdin.read()
        print("Reading from stdin")

    print("Scanning for secrets...")

    # Process content
    sanitized_content, stats = redact_secrets(content)

    # Output results
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(sanitized_content)
        print(f"Sanitized content written to: {args.output}")
    else:
        # Write to stdout
        sys.stdout.write(sanitized_content)
        print("\nSanitized content written to stdout")

    # Report on secrets found
    total_secrets = sum(stats.values())
    print(f"Found {total_secrets} potential secrets")

    if args.verbose or total_secrets > 0:
        print("Secret types detected:")
        if stats['AWS'] > 0:
            print(f"  - AWS Credentials: {stats['AWS']}")
        if stats['Azure'] > 0:
            print(f"  - Azure Credentials: {stats['Azure']}")
        if stats['API'] > 0:
            print(f"  - API Keys/Tokens: {stats['API']}")
        if stats['JWT'] > 0:
            print(f"  - JWT Tokens: {stats['JWT']}")
        if stats['Password'] > 0:
            print(f"  - Passwords: {stats['Password']}")
        if stats['Private'] > 0:
            print(f"  - Private Keys: {stats['Private']}")
        if stats['GitHub'] > 0:
            print(f"  - GitHub Tokens: {stats['GitHub']}")
        if stats['Google'] > 0:
            print(f"  - Google Credentials: {stats['Google']}")
        if stats['Generic'] > 0:
            print(f"  - Generic Secrets: {stats['Generic']}")


if __name__ == '__main__':
    main()
