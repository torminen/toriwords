#!/bin/sh
# Download the published dictionary.sqlite (GitHub Release asset) into ios/Resources/ and verify it
# against the committed tools/dictionary/dictionary.sqlite.sha256. A mismatch deletes the file and fails.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEST="$HERE/../../ios/Resources/dictionary.sqlite"
URL=$(sed -n 's/.*"asset_url": *"\([^"]*\)".*/\1/p' "$HERE/release.json")
WANT=$(cut -d' ' -f1 "$HERE/dictionary.sqlite.sha256")
[ -n "$URL" ] && [ -n "$WANT" ] || { echo "fetch.sh: cannot read release.json / dictionary.sqlite.sha256" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "$1" | cut -d' ' -f1; }
else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi

if [ -f "$DEST" ] && [ "$(sha "$DEST")" = "$WANT" ]; then echo "dictionary.sqlite is current ($WANT)"; exit 0; fi

echo "Downloading $URL"
curl -fL --retry 3 -o "$DEST.tmp" "$URL" || { rm -f "$DEST.tmp"; exit 1; }
GOT=$(sha "$DEST.tmp")
if [ "$GOT" != "$WANT" ]; then
  rm -f "$DEST.tmp" "$DEST"
  echo "fetch.sh: SHA-256 mismatch: got $GOT, expected $WANT. File deleted." >&2
  exit 1
fi
mv "$DEST.tmp" "$DEST"
echo "ios/Resources/dictionary.sqlite verified ($WANT)"
