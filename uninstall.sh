#!/bin/bash

set -euo pipefail

CLI="$HOME/.local/bin/reposync"
if [ ! -x "$CLI" ]; then
    echo "RepoSync is not installed at $CLI" >&2
    exit 1
fi

exec "$CLI" uninstall "$@"
