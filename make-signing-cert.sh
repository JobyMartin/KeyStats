#!/bin/bash
set -euo pipefail

# One-time setup: creates a self-signed code-signing identity ("KeyStats
# Local Signing") in the login keychain and trusts it for code signing.
#
# Why this exists: build-app.sh used to sign ad-hoc (`codesign --sign -`),
# which has no stable identity — macOS keys the Accessibility permission
# grant to the binary's CDHash, which changes on every rebuild. Signing with
# a real (even self-signed) identity gives the app a stable designated
# requirement, so the Accessibility grant survives rebuilds.
#
# Safe to re-run — exits immediately if the identity already exists.

IDENTITY_NAME="KeyStats Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "==> '$IDENTITY_NAME' already exists in $KEYCHAIN — nothing to do."
  security find-identity -v -p codesigning "$KEYCHAIN" | grep "$IDENTITY_NAME"
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> generating a 10-year self-signed code-signing certificate for '$IDENTITY_NAME'"

cat > "$WORKDIR/codesign.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $IDENTITY_NAME

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  -days 3650 \
  -config "$WORKDIR/codesign.cnf" \
  -extensions ext

openssl pkcs12 -export -legacy \
  -inkey "$WORKDIR/key.pem" \
  -in "$WORKDIR/cert.pem" \
  -out "$WORKDIR/identity.p12" \
  -name "$IDENTITY_NAME" \
  -passout pass:keystats

echo "==> importing into $KEYCHAIN (you may be prompted for your login password)"
security import "$WORKDIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P keystats \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "==> trusting the self-signed root for code signing"
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo "==> allowing codesign to use the key without a per-build prompt"
echo -n "Enter your login (keychain) password: "
read -rs LOGIN_PASSWORD
echo
if security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$LOGIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "    done"
else
  echo "    partition list step failed — codesign may prompt for keychain access on"
  echo "    first use instead. You can retry it later with:"
  echo "      security set-key-partition-list -S apple-tool:,apple:,codesign: -k <password> $KEYCHAIN"
fi
unset LOGIN_PASSWORD

echo "==> verifying"
security find-identity -v -p codesigning "$KEYCHAIN" | grep "$IDENTITY_NAME"

echo
echo "Done. build-app.sh will now sign with '$IDENTITY_NAME' instead of ad-hoc."
echo "You'll need to re-grant Accessibility permission ONE more time after the"
echo "next build (switching identities changes it once) — rebuilds after that"
echo "keep the grant."
