#!/bin/bash
# Setup GitHub Secrets for Sleight CI/CD (adapted from ltx-video-mac)
# Values are piped straight into gh secret set — never printed.
set -euo pipefail

REPO="james-see/sleight"
TEAM_ID="529AKJCKRC"

echo "=== Sleight - GitHub Secrets Setup ==="
echo ""

# Step 0: verify cert exists
CERT_SHA=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
if [ -z "$CERT_SHA" ]; then
    echo "ERROR: No Developer ID Application certificate found in your keychain."
    echo "Mint one first: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
    exit 1
fi
echo "Found Developer ID Application cert (SHA-1: $CERT_SHA)"
echo ""

# Step 1: export cert to p12 (temp file, deleted on exit)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
P12_FILE="$TEMP_DIR/certificate.p12"

read -s -p "Choose a password for the exported .p12 (gets stored as a secret, no need to remember): " CERT_PASS
echo ""
echo "Exporting certificate (macOS may prompt to allow keychain access — click Allow)..."
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -o "$P12_FILE" -P "$CERT_PASS"
echo "Exported."

# Step 2: set secrets
echo "Setting APPLE_DEVELOPER_ID_CERT..."
base64 -i "$P12_FILE" | gh secret set APPLE_DEVELOPER_ID_CERT -R "$REPO"

gh secret set APPLE_DEVELOPER_ID_CERT_PASSWORD -R "$REPO" -b "$CERT_PASS"
echo "Set APPLE_DEVELOPER_ID_CERT_PASSWORD"

KEYCHAIN_PASSWORD=$(openssl rand -hex 16)
gh secret set KEYCHAIN_PASSWORD -R "$REPO" -b "$KEYCHAIN_PASSWORD"
echo "Set KEYCHAIN_PASSWORD (random, CI-only)"

gh secret set APPLE_TEAM_ID -R "$REPO" -b "$TEAM_ID"
echo "Set APPLE_TEAM_ID ($TEAM_ID)"

read -p "Apple ID email [james@jamescampbell.us]: " APPLE_ID
APPLE_ID=${APPLE_ID:-james@jamescampbell.us}
gh secret set APPLE_ID -R "$REPO" -b "$APPLE_ID"
echo "Set APPLE_ID"

echo ""
echo "APPLE_ID_PASSWORD must be an App-Specific Password (not your Apple password):"
echo "  https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
echo "  (Reuse the one you made for ltx-video-mac if you still have it.)"
read -s -p "App-Specific Password: " APP_PASS
echo ""
gh secret set APPLE_ID_PASSWORD -R "$REPO" -b "$APP_PASS"
echo "Set APPLE_ID_PASSWORD"

echo ""
echo "=== Secrets configured for $REPO ==="
gh secret list -R "$REPO"
echo ""
echo "Cut the release with:"
echo "  cd ~/p/sleight && git tag v0.1.0 && git push origin v0.1.0"