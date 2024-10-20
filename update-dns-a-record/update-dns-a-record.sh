#!/bin/bash

#
# Author: Ove Ranheim (2020)
#
# Heartbeat script to update AWS Route53 A record for HOSTNAME.TLD
# The last updated ip is written to a receipt file used to check for ip changes.
# This eliminates unnecessary calls to aws.
# PS! if an IP is updated manually at Route53, it will not be detected by this script!
#
# To force possible update remove receipt file.
#
# Schedule every 30 mins and it will only updated if the public ip has changed.
#
# 1) Set up Route53 Public DNS.
# 2) Create User with Group Roles:  AmazonRoute53DomainsFullAccess and AmazonRoute53FullAccess.
# 3) `aws configure --profile AWS_CONFIG_PROFILE` with access key and secure access key.
# 4) `sudo crontab -e`
# content:
# --
#   SHELL=/bin/bash
#   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
#   */30 * * * * /path/to/update-dns-a-record.sh >> /var/log/dns-a-record-update.log
# --
#
# 5) `sudo crontab -l`
#

if [ ! "$(whoami)" == "root" ]; then
  echo "Root is required to run heartbeat script!"
  exit 1
fi

#
# User settings
#

PROFILE="AWS_CONFIG_PROFILE"
HOSTED_ZONE_ID="HOSTED_ZONE_ID"
HOSTNAME="HOSTNAME.TLD"
TTL=300

#
# Configure
#

export AWS_CONFIG_FILE=/var/root/.aws/config
export HOME=/var/root
LOGFILE=/var/log/dns-a-record-update.log
if [ ! -f "$LOGFILE" ]; then
  touch $LOGFILE
fi
LAST_PUBLIC_IP_RECEIPT_FILE=/tmp/dns-last-public-ip.txt

now() {
  date +'%Y-%m-%d %H:%M:%S'
}

echo "[$(now)] Check for new public ip.." >>$LOGFILE

#
# Check if network is available
#

if ! ping -q -t 2 -c 1 aws.amazon.com >/dev/null 2>&1; then
  echo "[$(now)] Network unavailable. Exiting!" >>$LOGFILE
  exit 1
fi

#
# Resolve current public ip
#

PUBLIC_IP=$(curl -s "https://checkip.amazonaws.com")

if [ -z "$PUBLIC_IP" ]; then
  echo "[$(now)] Unable to resolve public ip!" >>$LOGFILE
  exit 1
fi

#
# Read last resolved ip from file and verify. Exit if last updated A record mathces current public ip.
#

if [ -f "$LAST_PUBLIC_IP_RECEIPT_FILE" ]; then
  LAST_PUBLIC_IP=$(<$LAST_PUBLIC_IP_RECEIPT_FILE)
else
  LAST_PUBLIC_IP=""
fi

if [ "$PUBLIC_IP" == "$LAST_PUBLIC_IP" ]; then
  echo "[$(now)] No new ip detected ($LAST_PUBLIC_IP). Exiting!" >>$LOGFILE
  exit 1
fi

#
# Check if IP is a Proxy (e.g. if connected to NordVPN then exit)
#

IS_PUBLIC_IP_PROXY=$(curl -s "http://ip-api.com/json/${PUBLIC_IP}?fields=query,status,proxy" | jq .proxy)
if [ ! "$IS_PUBLIC_IP_PROXY" == "false" ]; then
  echo "[$(now)] VPN/Proxy decteded for ip: $PUBLIC_IP. Exiting!" >>$LOGFILE
  exit 1
fi

#
# Check last registered DNS A record and verify
#

DNS_IP=$(aws route53 --profile $PROFILE list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query "ResourceRecordSets[?Type == 'A'].ResourceRecords[0].Value" | jq -r '.[0]')

if [ "$PUBLIC_IP" == "$DNS_IP" ]; then
  echo "[$(now)] Current public ip $DNS_IP is already set!" >>$LOGFILE
  if [ ! -f "$LAST_PUBLIC_IP_RECEIPT_FILE" ]; then
    echo "$PUBLIC_IP" >$LAST_PUBLIC_IP_RECEIPT_FILE
  fi
  exit 0
else
  echo "[$(now)] Old adreess was $DNS_IP. Update to: $PUBLIC_IP" >>$LOGFILE
fi

#
# Prepare Route53 resource record set
#

TIMESTAMP=$(date +%s%3)
TMPFILE=$(mktemp /tmp/dns-a-record_"$TIMESTAMP".json)
cat >"${TMPFILE}" <<EOF
{
  "Comment": "CREATE/DELETE/UPSERT a record ",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$HOSTNAME",
        "Type": "A",
        "TTL": $TTL,
        "ResourceRecords": [
          {
            "Value": "$PUBLIC_IP"
          }
        ]
      }
    }
  ]
}
EOF

#
# Try to update A record with new public ip and write ip receipt file
#

if aws route53 --profile $PROFILE change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://"$TMPFILE" >>$LOGFILE 2>&1; then
  echo "$PUBLIC_IP" >$LAST_PUBLIC_IP_RECEIPT_FILE
  echo "[$(now)] Successfully updated $HOSTNAME with A record $PUBLIC_IP" >>$LOGFILE
fi

#
# Cleanup
#

rm -f "$TMPFILE"
