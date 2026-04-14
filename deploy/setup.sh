#!/usr/bin/env bash
#
# BizarreCRM deploy setup — generates nginx.conf from .env
#
# Usage:
#   bash deploy/setup.sh    # generate nginx.conf + print next steps
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Load BASE_DOMAIN from .env ──────────────────────────────────────────────
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "Copy .env.example to .env and set BASE_DOMAIN first."
  exit 1
fi

BASE_DOMAIN=$(grep -E '^BASE_DOMAIN=' "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "'"'"'')
if [ -z "$BASE_DOMAIN" ] || [ "$BASE_DOMAIN" = "localhost" ]; then
  echo "ERROR: BASE_DOMAIN in .env is '${BASE_DOMAIN:-unset}'"
  echo "Set it to your domain (e.g., BASE_DOMAIN=example.com) before running this script."
  exit 1
fi

echo "Domain: $BASE_DOMAIN"
echo ""

# ── Generate nginx.conf ─────────────────────────────────────────────────────
TEMPLATE="$SCRIPT_DIR/nginx.conf.template"
OUTPUT="$SCRIPT_DIR/nginx.conf"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: Template not found at $TEMPLATE"
  exit 1
fi

# Use envsubst to replace ${BASE_DOMAIN} while preserving nginx $variables
export BASE_DOMAIN
envsubst '${BASE_DOMAIN}' < "$TEMPLATE" > "$OUTPUT"
echo "Generated: deploy/nginx.conf (server_name: *.$BASE_DOMAIN $BASE_DOMAIN)"

# ── Cloudflare Setup ────────────────────────────────────────────────────────
CERT_DIR="/etc/ssl/cloudflare"
if [ ! -f "$CERT_DIR/origin.pem" ] 2>/dev/null; then
  echo ""
  echo "── Cloudflare Origin Certificate ──"
  echo ""
  echo "1. Cloudflare dashboard > SSL/TLS > Origin Server > Create Certificate"
  echo "2. Add both hostnames: $BASE_DOMAIN and *.$BASE_DOMAIN"
  echo "3. Copy the certificate PEM and private key PEM"
  echo "4. Save them on your server:"
  echo ""
  echo "   sudo mkdir -p $CERT_DIR"
  echo "   sudo nano $CERT_DIR/origin.pem      # paste certificate"
  echo "   sudo nano $CERT_DIR/origin-key.pem   # paste private key"
  echo "   sudo chmod 600 $CERT_DIR/origin-key.pem"
  echo ""
  echo "5. Set SSL mode to 'Full (Strict)' in Cloudflare > SSL/TLS"
fi

# ── DNS reminder ─────────────────────────────────────────────────────────────
echo ""
echo "── Cloudflare DNS ──"
echo ""
echo "Add these records in Cloudflare DNS:"
echo "  $BASE_DOMAIN        A    → your server IP   (Proxied)"
echo "  *.$BASE_DOMAIN      A    → your server IP   (DNS only — free plan)"
echo ""
echo "Note: Wildcard proxying (orange cloud) requires a paid Cloudflare plan."
echo "DNS-only (grey cloud) on the wildcard still lets Cloudflare handle the"
echo "bare domain, while subdomains connect directly to your origin."
echo "If you have a paid plan, you can proxy both."

# ── Install nginx config ────────────────────────────────────────────────────
echo ""
echo "── Next Steps ──"
echo ""
echo "1. Copy nginx config:"
echo "   sudo cp deploy/nginx.conf /etc/nginx/sites-available/bizarrecrm"
echo "   sudo ln -sf /etc/nginx/sites-available/bizarrecrm /etc/nginx/sites-enabled/"
echo ""
echo "2. Test and reload:"
echo "   sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "3. Start the CRM:"
echo "   cd packages/server && npx tsx src/index.ts"
echo ""
echo "Done! Tenants will be accessible at https://SLUG.$BASE_DOMAIN"
