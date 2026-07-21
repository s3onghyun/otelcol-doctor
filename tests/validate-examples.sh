#!/usr/bin/env bash
# Regression check for examples/.
#
# Asserts that each bundled example still behaves as documented against a current
# Collector build:
#   fixed-config.yaml       must VALIDATE  (it is the corrected config)
#   spanmetrics-config.yaml must VALIDATE  (advanced, documented as validated)
#   broken-config.yaml      must FAIL      (teaching example; bug 1 is the removed
#                                           `logging` exporter, so it cannot start)
#
# The two passing examples use ${env:...} endpoints. Validation resolves env
# expansion first, so they only validate with those variables set — that is what
# the placeholder values below are for. This is the reason a bare
# `validate --config=examples/fixed-config.yaml` reports
# `requires a non-empty "endpoint"`.
#
# Usage: tests/validate-examples.sh [collector-image]
set -uo pipefail

IMG="${1:-otel/opentelemetry-collector-contrib:0.154.0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples"

# Placeholder endpoints — only needed to satisfy env expansion during validation.
ENVS=(
  -e MIMIR_REMOTE_WRITE_URL=http://mimir:8080/api/v1/push
  -e TEMPO_OTLP_ENDPOINT=tempo:4317
  -e TEMPO_ENDPOINT=tempo:4317
  -e MIMIR_ENDPOINT=http://mimir:8080/api/v1/push
)

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found — install it or run 'otelcol-contrib validate' manually" >&2
  exit 2
fi

fail=0

check() {
  local file="$1" expect="$2" out rc
  out="$(docker run --rm "${ENVS[@]}" -v "$DIR/$file:/c.yaml" "$IMG" validate --config=/c.yaml 2>&1)"
  rc=$?
  if [[ "$expect" == "pass" ]]; then
    if [[ $rc -eq 0 ]]; then
      echo "ok    $file validates"
    else
      echo "FAIL  $file should validate but did not:"; echo "$out" | sed 's/^/        /'
      fail=1
    fi
  else
    if [[ $rc -ne 0 ]]; then
      echo "ok    $file fails as intended (teaching example)"
    else
      echo "FAIL  $file is supposed to be broken but validated clean"
      fail=1
    fi
  fi
}

echo "Collector image: $IMG"
check fixed-config.yaml       pass
check spanmetrics-config.yaml pass
check broken-config.yaml      fail

exit $fail
