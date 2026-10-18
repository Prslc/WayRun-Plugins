#!/bin/sh
# Refresh the `wayrun_plugin/` copy a plugin directory carries beside main.py.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
    echo "usage: $0 <plugin-dir>..." >&2
    exit 2
fi

for dir in "$@"; do
    mkdir -p "$dir"
    rm -rf "$dir/wayrun_plugin"
    cp -R "$root/wayrun_plugin" "$dir/wayrun_plugin"
    find "$dir/wayrun_plugin" -name __pycache__ -type d -prune -exec rm -rf {} +
done
