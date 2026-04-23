#!/bin/bash

# Cloudflare Configuration
source /home/ubuntu/.cloudflare-ddns.env
API_TOKEN="$CF_API_TOKEN"
ZONE_ID="$CF_ZONE_ID"
RECORD_NAME="$(hostname)"

# Get current public IP
IP=$(curl -s https://api.ipify.org)

# Get existing DNS record info
RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json")

RECORD_ID=$(echo $RECORD_INFO | grep -oP '(?<="id":")[^"]+' | head -n 1)
OLD_IP=$(echo $RECORD_INFO | grep -oP '(?<="content":")[^"]+' | head -n 1)

if [ "$IP" != "$OLD_IP" ]; then
    echo "IP changed from $OLD_IP to $IP. Updating Cloudflare..."
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
         -H "Authorization: Bearer $API_TOKEN" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$IP\",\"ttl\":120,\"proxied\":false}"
else
    echo "IP has not changed ($IP)."
fi
