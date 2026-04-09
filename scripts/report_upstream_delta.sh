#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
OLD_COMMIT="${2:?old upstream commit required}"
NEW_COMMIT="${3:?new upstream commit required}"
SOURCE_PATH="${4:-vendor/rig/rig/rig-core}"
LANGUAGE="${5:-rust}"

SOURCE_MANIFEST="${ROOT_DIR}/plans/inventory/${LANGUAGE}_source_parity.tsv"
TEST_MANIFEST="${ROOT_DIR}/plans/inventory/${LANGUAGE}_test_parity.tsv"
PORT_MANIFEST="${ROOT_DIR}/plans/inventory/${LANGUAGE}_port_inventory.tsv"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCE_ABS="${ROOT_DIR}/${SOURCE_PATH}"
UPSTREAM_GIT_DIR="$(cd "${SOURCE_ABS}" && git rev-parse --show-toplevel)"
UPSTREAM_REL="${SOURCE_ABS#$UPSTREAM_GIT_DIR/}"

echo "Upstream delta: ${OLD_COMMIT}..${NEW_COMMIT}"
echo "Source path: ${UPSTREAM_REL}"
echo
echo "Changed files:"
git -C "${UPSTREAM_GIT_DIR}" diff --name-status "${OLD_COMMIT}..${NEW_COMMIT}" -- "${UPSTREAM_REL}"
echo

"${ROOT_DIR}/scripts/generate_source_parity_manifest.sh" "${ROOT_DIR}" "${TMP_DIR}/source.tsv" "${SOURCE_PATH}" "${LANGUAGE}"
"${ROOT_DIR}/scripts/generate_test_parity_manifest.sh" "${ROOT_DIR}" "${TMP_DIR}/test.tsv" "${SOURCE_PATH}" "${LANGUAGE}"
"${ROOT_DIR}/scripts/generate_port_inventory.sh" "${ROOT_DIR}" "${TMP_DIR}/port.tsv" "${SOURCE_PATH}" "${LANGUAGE}"

echo "New source parity IDs not in checked-in source manifest:"
comm -13 <(cut -f1 "${SOURCE_MANIFEST}" | sort) <(cut -f1 "${TMP_DIR}/source.tsv" | sort) || true
echo
echo "New test parity IDs not in checked-in test manifest:"
comm -13 <(cut -f1 "${TEST_MANIFEST}" | sort) <(cut -f1 "${TMP_DIR}/test.tsv" | sort) || true
echo
echo "Port inventory rows missing from checked-in curated inventory:"
python3 - <<'PY' "${PORT_MANIFEST}" "${TMP_DIR}/port.tsv"
from pathlib import Path
import sys
curated = Path(sys.argv[1])
generated = Path(sys.argv[2])
cur_ids = {line.split('\t')[0] for line in curated.read_text().splitlines() if line.strip() and not line.startswith('#')}
for line in generated.read_text().splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    if line.split('\t')[0] not in cur_ids:
        print(line)
PY
echo
echo "Stale curated inventory rows no longer emitted by generator:"
python3 - <<'PY' "${PORT_MANIFEST}" "${TMP_DIR}/port.tsv"
from pathlib import Path
import sys
curated = Path(sys.argv[1])
generated = Path(sys.argv[2])
gen_ids = {line.split('\t')[0] for line in generated.read_text().splitlines() if line.strip() and not line.startswith('#')}
for line in curated.read_text().splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    if line.split('\t')[0] not in gen_ids:
        print(line)
PY
