#!/usr/bin/env bash
# Compila el binario estático (musl) de landlock_rosh.
# Requiere: rustup target add x86_64-unknown-linux-musl
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release --target x86_64-unknown-linux-musl

SRC="${CARGO_TARGET_DIR:-target}/x86_64-unknown-linux-musl/release/landlock_rosh"
# El crate vive en src/tools/landlock/crate; el binario que se empaqueta
# (imagen + --install-tools) va a src/tools/landlock_rosh.
DEST="${1:-$(cd "$(dirname "$0")/../.." && pwd)/landlock_rosh}"
cp "$SRC" "$DEST"
chmod 755 "$DEST"

echo "OK -> $DEST ($(stat -c%s "$DEST") bytes, $(file -b "$DEST" | cut -d, -f1,3))"
