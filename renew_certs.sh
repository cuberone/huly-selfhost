#!/bin/bash
# Run `certbot renew`, then HUP nginx so it picks up any renewed cert.
# Idempotent — certbot only actually renews when <30 days left. Safe to run
# daily. Designed to be called from a host cron:
#
#   23 3 */2 * *  /home/ubuntu/huly-selfhost/renew_certs.sh >> /var/log/certbot-renew.log 2>&1
#
# Adding/removing domains is NOT a renew operation — use ./issue_certs.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker compose -p huly --profile certbot -f compose.yml --env-file huly_v7.conf \
  run --rm certbot renew --quiet --non-interactive

# Only reload if renewal actually changed something. certbot's `renew` is a
# no-op most days, so we always call `nginx -t` + HUP to keep the script
# idempotent; nginx reload is cheap and drops no connections.
if docker exec huly-nginx-1 nginx -t >/dev/null 2>&1; then
  docker kill --signal=HUP huly-nginx-1 >/dev/null
else
  echo "WARN: nginx -t failed after renew; falling back to restart" >&2
  docker compose -p huly -f compose.yml --env-file huly_v7.conf restart nginx
fi
