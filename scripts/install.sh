#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${MEDIA_HUB_PREFIX:-$HOME/.local}"
LIB_DIR="${MEDIA_HUB_LIB_DIR:-$PREFIX/lib/media-hub}"
BIN_DIR="${MEDIA_HUB_BIN_DIR:-$PREFIX/bin}"
CONFIG_DIR="${MEDIA_HUB_CONFIG_DIR:-$HOME/.config/media-hub}"
DATA_DIR="${MEDIA_HUB_DATA_DIR:-$HOME/.local/share/media-hub}"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMAGE_PREFIX="${MEDIA_HUB_IMAGE_PREFIX:-media-hub}"
BUILD_IMAGES=1
OVERWRITE_CONFIG=0
INSTALL_SYSTEMD=0
TIMER_ON_CALENDAR="${MEDIA_HUB_TIMER_ON_CALENDAR:-hourly}"
RANDOMIZED_DELAY="${MEDIA_HUB_RANDOMIZED_DELAY:-5m}"

usage() {
  cat <<EOF
Usage: scripts/install.sh [options]

Installs media-hub runtime scripts under ~/.local and optionally builds worker images locally.

Options:
  --no-build           Do not build worker container images
  --overwrite-config   Overwrite existing ~/.config/media-hub/*.yaml files
  --install-systemd    Install and enable a systemd user timer
  --on-calendar VALUE  systemd OnCalendar value for timer (default: hourly)
  -h, --help           Show this help

Environment overrides:
  MEDIA_HUB_PREFIX       default: $HOME/.local
  MEDIA_HUB_LIB_DIR      default: ~/.local/lib/media-hub
  MEDIA_HUB_BIN_DIR      default: ~/.local/bin
  MEDIA_HUB_CONFIG_DIR   default: ~/.config/media-hub
  MEDIA_HUB_DATA_DIR     default: ~/.local/share/media-hub
  MEDIA_HUB_IMAGE_PREFIX default: media-hub
  MEDIA_HUB_TIMER_ON_CALENDAR default: hourly
  MEDIA_HUB_RANDOMIZED_DELAY default: 5m
  CONTAINER_RUNTIME      default: podman
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD_IMAGES=0; shift ;;
    --overwrite-config) OVERWRITE_CONFIG=1; shift ;;
    --install-systemd) INSTALL_SYSTEMD=1; shift ;;
    --on-calendar) TIMER_ON_CALENDAR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

mkdir -p "$LIB_DIR" "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR"
rm -rf "$LIB_DIR/scripts" "$LIB_DIR/db" "$LIB_DIR/config" "$LIB_DIR/schemas" "$LIB_DIR/workers"
cp -R "$ROOT_DIR/scripts" "$LIB_DIR/scripts"
cp -R "$ROOT_DIR/db" "$LIB_DIR/db"
cp -R "$ROOT_DIR/config" "$LIB_DIR/config"
cp -R "$ROOT_DIR/schemas" "$LIB_DIR/schemas"
cp -R "$ROOT_DIR/workers" "$LIB_DIR/workers"
cp "$ROOT_DIR/README.md" "$LIB_DIR/README.md"
rm -rf "$LIB_DIR/workers/bluesky/node_modules" "$LIB_DIR/workers/bluesky/dist"
find "$LIB_DIR/workers" -type d -name __pycache__ -prune -exec rm -rf {} +
chmod +x "$LIB_DIR/scripts"/*.sh

install_config() {
  local name="$1"
  local src=""
  if [[ -f "$ROOT_DIR/config/$name.local.yaml" ]]; then
    src="$ROOT_DIR/config/$name.local.yaml"
  else
    src="$ROOT_DIR/config/$name.example.yaml"
  fi
  if [[ ! -f "$CONFIG_DIR/$name.yaml" || "$OVERWRITE_CONFIG" -eq 1 ]]; then
    cp "$src" "$CONFIG_DIR/$name.yaml"
    echo "installed config $CONFIG_DIR/$name.yaml" >&2
  else
    echo "kept existing config $CONFIG_DIR/$name.yaml" >&2
  fi
}

install_config rss
install_config bluesky
install_config polymarket

make_wrapper() {
  local name="$1"
  local target="$2"
  cat > "$BIN_DIR/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export MEDIA_HUB_CONFIG_DIR="\${MEDIA_HUB_CONFIG_DIR:-$CONFIG_DIR}"
export MEDIA_HUB_DATA_DIR="\${MEDIA_HUB_DATA_DIR:-$DATA_DIR}"
export MEDIA_HUB_DB="\${MEDIA_HUB_DB:-\$MEDIA_HUB_DATA_DIR/media-hub.sqlite}"
export MEDIA_HUB_SCHEMA="\${MEDIA_HUB_SCHEMA:-$LIB_DIR/db/schema.sql}"
exec "$LIB_DIR/scripts/$target" "\$@"
EOF
  chmod +x "$BIN_DIR/$name"
}

make_wrapper media-hub-build build.sh
make_wrapper media-hub-debug-tick debug-tick.sh
make_wrapper media-hub-ingest ingest.sh
make_wrapper media-hub-init-db init-db.sh
make_wrapper media-hub-items items.sh
make_wrapper media-hub-search search.sh
make_wrapper media-hub-tick tick.sh

if [[ "$BUILD_IMAGES" -eq 1 ]]; then
  MEDIA_HUB_IMAGE_PREFIX="$IMAGE_PREFIX" CONTAINER_RUNTIME="$RUNTIME" "$ROOT_DIR/scripts/build.sh"
fi

MEDIA_HUB_SCHEMA="$LIB_DIR/db/schema.sql" MEDIA_HUB_DB="$DATA_DIR/media-hub.sqlite" "$LIB_DIR/scripts/init-db.sh" >/dev/null

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$SYSTEMD_USER_DIR"
  cat > "$SYSTEMD_USER_DIR/media-hub.service" <<EOF
[Unit]
Description=Run media-hub ingestion tick
Documentation=file://$LIB_DIR/README.md

[Service]
Type=oneshot
Environment=MEDIA_HUB_CONFIG_DIR=$CONFIG_DIR
Environment=MEDIA_HUB_DATA_DIR=$DATA_DIR
Environment=MEDIA_HUB_DB=$DATA_DIR/media-hub.sqlite
Environment=MEDIA_HUB_SCHEMA=$LIB_DIR/db/schema.sql
Environment=MEDIA_HUB_IMAGE_PREFIX=$IMAGE_PREFIX
Environment=CONTAINER_RUNTIME=$RUNTIME
ExecStart=$BIN_DIR/media-hub-tick
EOF

  cat > "$SYSTEMD_USER_DIR/media-hub.timer" <<EOF
[Unit]
Description=Run media-hub ingestion on a schedule

[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=$RANDOMIZED_DELAY

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now media-hub.timer
fi

cat >&2 <<EOF
Installed media-hub runtime.

Binaries: $BIN_DIR/media-hub-*
Config:   $CONFIG_DIR/*.yaml
Data:     $DATA_DIR/media-hub.sqlite
Images:   $IMAGE_PREFIX-{rss,bluesky,polymarket}
EOF

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  cat >&2 <<EOF
Systemd:  media-hub.timer enabled ($TIMER_ON_CALENDAR, randomized delay $RANDOMIZED_DELAY)

Useful commands:
  systemctl --user status media-hub.timer
  systemctl --user list-timers media-hub.timer
  journalctl --user -u media-hub.service
EOF
else
  cat >&2 <<EOF

Manual command:
  $BIN_DIR/media-hub-tick

Install systemd timer:
  $ROOT_DIR/scripts/install.sh --install-systemd
EOF
fi
