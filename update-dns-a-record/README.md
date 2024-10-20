# AWS Route53 Dynamic A Record Updater

This Bash script updates an AWS Route53 A record for a given domain name with the current public IP of your host. The script is useful for dynamically updating DNS records when your public IP changes, typically due to DHCP or changing network environments. 

## How It Works

- The script checks the current public IP of the host.
- It compares the current public IP to the last known IP stored in a receipt file.
- If the IP has changed, it updates the Route53 DNS A record.
- The script also logs the actions and IP changes to a log file.

## Features

- Detects and updates public IP changes.
- Prevents unnecessary calls to AWS if the IP hasn’t changed.
- VPN/Proxy detection: Does not update DNS if the public IP is detected as a proxy.
- Scheduled updates using cron (recommended to run every 30 minutes).
- Logging of all actions and updates for auditing.
- Configurable via environment variables.

## Requirements

- AWS CLI configured with access to Route53.
- jq (command-line JSON processor).
- Root privileges.
- A hosted zone and domain set up in AWS Route53.

## Installation

1. Install dependencies:
   - AWS CLI: [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
   - jq: Install jq with your package manager (e.g., `sudo apt-get install jq` on Ubuntu).

2. Configure AWS CLI:
   ```bash
   aws configure --profile AWS_CONFIG_PROFILE
   ```
   Ensure the profile has sufficient permissions, specifically `AmazonRoute53DomainsFullAccess` and `AmazonRoute53FullAccess`.

3. Clone this repository and place the script in a directory of your choice:
   ```bash
   git clone https://github.com/your-repo/aws-route53-dns-updater.git
   ```

4. Make the script executable:
   ```bash
   chmod +x update-dns-a-record.sh
   ```

5. Set up cron to run the script every 30 minutes:
   ```bash
   sudo crontab -e
   ```
   Add the following line to the crontab:
   ```bash
    SHELL=/bin/bash
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    */30 * * * * /path/to/update-dns-a-record.sh >> /var/log/dns-a-record-update.log 2>&1
   ```

## Configuration

Edit the script and update the following user settings according to your environment:

```bash
PROFILE="AWS_CONFIG_PROFILE"      # AWS CLI profile to use
HOSTED_ZONE_ID="HOSTED_ZONE_ID"   # Route53 Hosted Zone ID
HOSTNAME="HOSTNAME.TLD"           # Domain name to update
TTL=300                           # Time to live for the DNS record
```

Optionally, you can also configure the log file location:

```bash
LOGFILE=/var/log/dns-a-record-update.log
```

## Usage

Once configured, the script can be manually run or scheduled with cron. It will automatically:
- Check the network availability.
- Resolve the public IP.
- Compare it to the last known public IP.
- Update the Route53 A record if necessary.

### Manual Execution

To run the script manually:
```bash
sudo ./update-dns-a-record.sh
```

## Logs

The script writes logs to `/var/log/dns-a-record-update.log`. Logs include timestamps, actions taken, and IP changes. 

## Troubleshooting

- **Permission Denied**: Ensure the script is run as root.
- **AWS CLI Errors**: Ensure your AWS CLI is configured correctly and the profile has the correct permissions.
- **No IP Change Detected**: The script will not update Route53 if the public IP has not changed since the last check.

