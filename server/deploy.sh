#!/usr/bin/env bash
set -euo pipefail

host="${GOOSE_ART_HOST:-root@goose-art.maxbickers.com}"
cd "$(dirname "${BASH_SOURCE[0]}")"

# git ls-files keeps the droplet's .venv and __pycache__ out of the transfer
git ls-files | rsync -a --files-from=- ./ "$host:/opt/goose-art/"

ssh "$host" 'set -e
cd /opt/goose-art
uv sync --frozen
install -m 644 goose-art.service /etc/systemd/system/goose-art.service
systemctl daemon-reload
systemctl enable goose-art
systemctl restart goose-art'
