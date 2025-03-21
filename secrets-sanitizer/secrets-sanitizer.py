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
    # AWS
    (r'AKIA[A-Z0-9]{16}', '[AWS-KEY]'),
    (r'aws_secret_access_key\s*=\s*["\']?[A-Za-z0-9+/=]{20,}["\']?', r'aws_secret_access_key = "[AWS-SECRET]"'),
    (r'"secret_key"\s*:\s*"[A-Za-z0-9+/=]{20,}"', r'"secret_key": "[AWS-SECRET]"'),
    (r'aws_session_token\s*=\s*["\'][A-Za-z0-9+/=]{100,}["\']', r'aws_session_token = "[AWS-SESSION-TOKEN]"'),

    # Azure
    (r'AccountKey=[A-Za-z0-9+/=]{50,}', r'AccountKey=[AZURE-KEY]'),
    (r'sig=[A-Za-z0-9%+/=]{30,}', r'sig=[AZURE-SAS]'),
    (r'AZURE_STORAGE_SAS_TOKEN="[^"]*"', r'AZURE_STORAGE_SAS_TOKEN="[AZURE-SAS]"'),
    (r'(AZURE_API_KEY(?:_\d+)?)=([^=\s\[\]]+)', r'\1=[API-KEY]'),

    # API Keys
    (r'API_KEY\s*=\s*["\']?[A-Za-z0-9]{20,}["\']?', r'API_KEY = "[API-KEY]"'),
    (r'([A-Z_]*API_KEY[A-Z0-9_]*)=([^=\s\[\]]+)', r'\1=[API-KEY]'),
    (r'(AZURE|APPSETTING).*API_KEY.*=([^=\s\[\]]+)', r'\1=[API-KEY]'),
    (r'"key"\s*:\s*"[A-Za-z0-9]{20,}"', r'"key": "[API-KEY]"'),

    # Auth/Bearer Tokens
    (r'AUTH_TOKEN\s*=\s*["\']?[A-Za-z0-9._-]{10,}["\']?', r'AUTH_TOKEN = "[AUTH-TOKEN]"'),
    (r'Authorization token: [A-Za-z0-9._-]{10,}', r'Authorization token: [AUTH-TOKEN]'),
    (r'Bearer\s+[A-Za-z0-9._-]{10,}', r'Bearer [BEARER-TOKEN]'),

    # JWT
    (r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', '[JWT-TOKEN]'),

    # Passwords
    (r'Password=[^;"\']+'';', r'Password=[PASSWORD];'),
    (r'password\s*=\s*"[^"]*"', r'password = "[PASSWORD]"'),
    (r'"password"\s*:\s*"[^"]*"', r'"password": "[PASSWORD]"'),
    # Handle "key=value=True" properly by preserving the trailing content
    (r'([A-Za-z0-9_]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_]*)=([^=\s\n]*)(?:(=.*))?', r'\1=[PASSWORD]\3'),
    (r'([A-Za-z0-9_]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][A-Za-z0-9_]*)="([^"]*)"', r'\1="[PASSWORD]"'),

    # GitHub
    (r'ghp_[A-Za-z0-9]{36}', '[GITHUB-TOKEN]'),

    # Google
    (r'AIza[A-Za-z0-9_-]{35}', '[GOOGLE-API-KEY]'),
    (r'[0-9]{12}-[A-Za-z0-9_]{32}\.apps\.googleusercontent\.com', '[GOOGLE-OAUTH]'),

    # Generic secrets in env vars - capture just the value, preserving trailing "=True" etc.
    (r'([A-Z][A-Z0-9_]*(?:_\d+)?(?:SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Z0-9_]*)=([^=\s\n]*)(?:(=.*))?',
     r'\1=[SECRET]\3'),
    (r'([A-Z][A-Z0-9_]*(?:_\d+)?(?:SECRET|KEY|TOKEN|AUTH|CRED|SIGN|IDENTITY|MSI)[A-Z0-9_]*)="([^"]*)"',
     r'\1="[SECRET]"'),
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
    """Redact secrets from text content."""
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

    # Track redacted regions to prevent double-redaction
    redacted_regions = set()

    # First, apply special processing for private keys
    content, private_key_count = redact_private_keys(content)
    stats['Private'] = private_key_count

    # Try to process as JSON
    json_content, json_count = process_json_content(content)
    if json_count > 0:
        content = json_content
        stats['API'] += json_count

    # Apply regex patterns
    for pattern, replacement in SECRET_PATTERNS:
        # Find all matches
        for match in re.finditer(pattern, content):
            start, end = match.span()

            # Check if this region has already been redacted
            overlaps = False
            for s, e in redacted_regions:
                if start < e and end > s:
                    overlaps = True
                    break

            if not overlaps:
                # Process this match
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
                elif '[GITHUB-TOKEN]' in replacement:
                    stats['GitHub'] += 1
                elif '[GOOGLE-' in replacement:
                    stats['Google'] += 1
                else:
                    stats['Generic'] += 1

                # Add to redacted regions
                redacted_regions.add((start, end))

        # Apply the pattern
        content = re.sub(pattern, replacement, content)

    return content, stats


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
