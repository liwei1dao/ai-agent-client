#!/bin/sh
set -e

cd /app
mkdir -p ./log

echo "[entrypoint] starting yunyan-console..."
exec /opt/console/console -conf ./confs/console.yaml
