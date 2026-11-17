#!/usr/bin/env bash
# Start a dedicated No Man's Drive world from a checkout: ./server.sh
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
PORT="${PORT:-24680}"
SEED="${SEED:-4242}"
MAP="${MAP:-starter}"
case "$PORT" in ''|*[!0-9]*) echo "PORT must be numeric" >&2; exit 2;; esac
if (( PORT < 1 || PORT > 65535 )); then echo "PORT must be 1..65535" >&2; exit 2; fi
GODOT_VERSION=4.6.3
ENGINE="${GODOT_BIN:-}"
if [[ -z "$ENGINE" ]]; then
  for candidate in godot godot4; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version 2>/dev/null | grep -q '^4\.6\.'; then
      ENGINE="$(command -v "$candidate")"; break
    fi
  done
fi
if [[ -z "$ENGINE" ]]; then
  mkdir -p .server-bin
  ENGINE="$ROOT/.server-bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
  if [[ ! -x "$ENGINE" ]]; then
    command -v curl >/dev/null || { echo 'Install curl first.' >&2; exit 2; }
    command -v unzip >/dev/null || { echo 'Install unzip first.' >&2; exit 2; }
    URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
    echo "Downloading Godot $GODOT_VERSION (once)..."
    curl -fL --retry 3 "$URL" -o .server-bin/godot.zip
    unzip -qo .server-bin/godot.zip -d .server-bin
    chmod +x "$ENGINE"
    rm -f .server-bin/godot.zip
  fi
fi
mkdir -p "$ROOT/server-data"
export XDG_DATA_HOME="$ROOT/server-data"
echo "No Man's Drive: UDP port $PORT, seed $SEED, map $MAP"
echo "Friends connect in Co-op with the server's public IP or domain (add :$PORT if nondefault)."
echo "Forward/allow UDP $PORT. Server data remains under server-data/. Ctrl+C to stop."
exec "$ENGINE" --headless --path "$ROOT/game" -- --dedicated "--port=$PORT" "--seed=$SEED" "--map=$MAP"
