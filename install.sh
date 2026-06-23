#!/usr/bin/env bash
set -euo pipefail

PROJECT_URL="https://github.com/cpiz/scp-speedtest"
VERSION="${VERSION:-v1.1.0}"
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-${PREFIX}/bin}"
BIN="${BIN:-scp-speedtest}"
SOURCE_URL="${SCP_SPEEDTEST_URL:-https://raw.githubusercontent.com/cpiz/scp-speedtest/${VERSION}/scp-speedtest.sh}"
LOCAL_SCRIPT="${SCP_SPEEDTEST_LOCAL_SCRIPT:-}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/scp-speedtest-install.XXXXXX")"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [[ -z "$LOCAL_SCRIPT" && -f "./scp-speedtest.sh" ]]; then
  LOCAL_SCRIPT="./scp-speedtest.sh"
fi

if [[ -n "$LOCAL_SCRIPT" ]]; then
  cp "$LOCAL_SCRIPT" "${tmp_dir}/${BIN}"
else
  if ! command -v curl >/dev/null 2>&1; then
    printf 'Error: curl is required to download scp-speedtest.\n' >&2
    exit 1
  fi
  curl -fsSL "$SOURCE_URL" -o "${tmp_dir}/${BIN}"
fi

chmod 0755 "${tmp_dir}/${BIN}"

if ! install -d "$BINDIR" 2>/dev/null || ! install -m 0755 "${tmp_dir}/${BIN}" "${BINDIR}/${BIN}" 2>/dev/null; then
  printf 'Error: failed to install to %s. Try running with sudo or set PREFIX to a writable path.\n' "$BINDIR" >&2
  exit 1
fi

printf 'Installed %s to %s\n' "$BIN" "${BINDIR}/${BIN}"
printf 'Project: %s\n' "$PROJECT_URL"
