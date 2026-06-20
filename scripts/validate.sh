#!/usr/bin/env bash
# Validate an OpenTelemetry Collector config without starting the Collector.
# Tries, in order: otelcol-contrib, otelcol, then a Docker contrib image.
#
# Usage: scripts/validate.sh path/to/config.yaml
set -euo pipefail

CONFIG="${1:-}"
if [[ -z "$CONFIG" || ! -f "$CONFIG" ]]; then
  echo "usage: $0 <config.yaml>" >&2
  exit 2
fi

if command -v otelcol-contrib >/dev/null 2>&1; then
  echo "→ otelcol-contrib validate"
  exec otelcol-contrib validate --config="$CONFIG"
elif command -v otelcol >/dev/null 2>&1; then
  echo "→ otelcol validate (core; contrib-only components will report as unknown)"
  exec otelcol validate --config="$CONFIG"
elif command -v docker >/dev/null 2>&1; then
  echo "→ no local binary; validating via Docker (contrib image)"
  exec docker run --rm -v "$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG"):/c.yaml" \
    otel/opentelemetry-collector-contrib:latest validate --config=/c.yaml
else
  echo "No otelcol / otelcol-contrib / docker found. Install one:" >&2
  echo "  https://opentelemetry.io/docs/collector/installation/" >&2
  exit 127
fi
