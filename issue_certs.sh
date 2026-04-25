#!/bin/bash
# Issue or expand the Let's Encrypt cert used by nginx. Reads hostnames from
# certbot/domains.txt
# (the --cert-name is hardcoded so the nginx path stays stable regardless of
# which domain is listed first).
#
# First-time use:  ./issue_certs.sh --dry-run      # staging, no real cert
#                  ./issue_certs.sh                # real issuance
# Add a domain:    append to certbot/domains.txt, then ./issue_certs.sh
# After success:   reload nginx (issue_certs.sh does this for you).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load LETSENCRYPT_EMAIL (and everything else) from the env file.
set -a
# shellcheck disable=SC1091
. ./huly_v7.conf
set +a

if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
  echo "ERROR: LETSENCRYPT_EMAIL is empty in huly_v7.conf" >&2
  exit 1
fi

# Build -d flags from domains.txt (skip blank lines and #comments).
D_FLAGS=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="${line//[[:space:]]/}"
  [[ -z "$line" ]] && continue
  D_FLAGS+=(-d "$line")
done < certbot/domains.txt

if [[ ${#D_FLAGS[@]} -eq 0 ]]; then
  echo "ERROR: certbot/domains.txt has no active hostnames" >&2
  exit 1
fi

EXTRA_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      # certbot's own --dry-run hits the staging CA AND skips writing cert
      # files to disk. Using --staging instead would persist a staging cert
      # that then blocks the next real run via --keep-until-expiring.
      EXTRA_ARGS+=(--dry-run)
      echo "DRY RUN: validates against Let's Encrypt staging CA; no cert written."
      ;;
    *) EXTRA_ARGS+=("$arg") ;;
  esac
done

echo "Issuing/updating cert for: ${D_FLAGS[*]}"

# --expand updates the existing cert if the SAN list changed.
# --cert-name huly pins the on-disk path regardless of domain ordering.
# --webroot points certbot at the shared volume served by nginx at :80.
docker compose -p huly --profile certbot -f compose.yml --env-file huly_v7.conf \
  run --rm certbot certonly \
    --webroot --webroot-path /var/www/certbot \
    --cert-name huly \
    --non-interactive --agree-tos --no-eff-email \
    --email "$LETSENCRYPT_EMAIL" \
    --expand --keep-until-expiring \
    "${D_FLAGS[@]}" "${EXTRA_ARGS[@]}"

# Reload nginx so it picks up the new cert files. nginx -t first so a typo
# doesn't take the proxy down.
if docker exec huly-nginx-1 nginx -t 2>&1; then
  docker kill --signal=HUP huly-nginx-1 >/dev/null
  echo "nginx reloaded."
else
  echo "WARN: nginx -t failed; not reloading. Fix config and run: docker kill --signal=HUP huly-nginx-1" >&2
  exit 1
fi
