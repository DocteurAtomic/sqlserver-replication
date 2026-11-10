#!/usr/bin/env bash
# Downloads the backup, checks it, starts the three instances, prepares the snapshot folder on
# the shared volume and restores PachadataTraining on rpllab1, then checks the lab with
# setup/test-lab.sh. The lab is left without any replication: each module builds what it needs.
# Usage: ./setup/install.sh
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./setup/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
compose=${COMPOSE:-docker compose}
export ENGINE=${ENGINE:-docker}
. setup/lib.sh
bak=PachadataTraining-2026-10.bak
mkdir -p setup/backup

fetch() {  # name, url, sha256
    local f=setup/backup/$1
    if [ ! -f "$f" ]; then
        echo "Downloading $1..."
        curl -fL --retry 3 -o "$f.part" "$2"
        mv "$f.part" "$f"
    fi
    local got
    if command -v sha256sum >/dev/null; then got=$(sha256sum "$f" | cut -d' ' -f1)
    else got=$(shasum -a 256 "$f" | cut -d' ' -f1); fi
    if [ "$got" != "$3" ]; then
        echo "Checksum mismatch for $f: delete it and run this script again." >&2
        exit 1
    fi
}
fetch $bak \
    'https://files.pachadata.com/public/api/raw?hash=tAsyC50c6kfVadBp3zc6TQ&file=/PachadataTraining/SqlServer/PachadataTraining-2026-10.bak' \
    1d05970d8e0576cd0c57bddba64c2ba8a583845ad4744adeb75d2ea4a3f7d44e

$compose up -d --wait
# The shared volume is created empty and owned by root: SQL Server runs as mssql.
$engine exec -u 0 rpllab1 mkdir -p /var/opt/mssql/share/repldata
$engine exec -u 0 rpllab1 chown -R mssql:mssql /var/opt/mssql/share
if [ -z "$($engine exec rpllab1 ls /var/opt/mssql/share/$bak 2>/dev/null)" ]; then
    $engine cp setup/backup/$bak rpllab1:/var/opt/mssql/share/$bak
    $engine exec -u 0 rpllab1 chown mssql:mssql /var/opt/mssql/share/$bak
fi
sql rpllab1 < setup/restore.sql
./setup/test-lab.sh
