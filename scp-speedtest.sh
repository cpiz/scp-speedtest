#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  printf 'Error: this script requires bash. Run it with: bash %s\n' "$0" >&2
  exit 2
fi
if shopt -oq posix; then
  printf 'Error: this script requires bash mode. Run it with: bash %s\n' "$0" >&2
  exit 2
fi

set -euo pipefail

VERSION="1.0.2"
DEFAULT_SIZE="100M"
PROJECT_URL="https://github.com/cpiz/scp-speedtest"

TARGET=""
HOST=""
USER_NAME=""
PORT=""
IDENTITY_FILE=""
SSH_CONFIG=""
JUMP_HOST=""
CONNECT_TIMEOUT=""
MAX_DURATION=""
ROUNDS=1
SIZE="$DEFAULT_SIZE"
SIZE_LABEL="$DEFAULT_SIZE"
TEST_BYTES=0
REMOTE_DIR=""
REMOTE_FILE_METHOD="auto"
LEGACY_SCP=0
JSON_OUTPUT=0
KEEP_FILES=0
DRY_RUN=0
QUIET=0
SHOW_SSH_WARNINGS=0
POSITIONAL_TARGET=""
SSH_OPTIONS=()
SSH_CMD=()
SCP_CMD=()
WARN_WEAK_CRYPTO_SUPPORTED=""

LOCAL_TMP_DIR=""
LOCAL_DOWNLOAD_DIR=""
REMOTE_TMP_DIR=""
REMOTE_TMP_CREATED=0
REMOTE_SPEC=""
REMOTE_TEST_FILE=""
TEST_FILE_NAME="scp-speedtest-${DEFAULT_SIZE}.bin"
TRANSFER_INTERRUPTED=0
LAST_SCP_STATUS=0

UPLOAD_STATUS="skipped"
UPLOAD_BYTES=0
UPLOAD_SECONDS="0.000000"
UPLOAD_MIBPS="0.00"
DOWNLOAD_STATUS="skipped"
DOWNLOAD_BYTES=0
DOWNLOAD_SECONDS="0.000000"
DOWNLOAD_MIBPS="0.00"
STARTED_AT=""
ENDED_AT=""
REMOTE_GENERATOR=""
REMOTE_GENERATOR_STATUS="skipped"
CURRENT_STEP=""
ERROR_CARD_PRINTED=0
ROUND_INDEX=1
ROUND_STARTED_ATS=()
ROUND_ENDED_ATS=()
ROUND_REMOTE_DIRS=()
ROUND_REMOTE_GENERATORS=()
ROUND_REMOTE_GENERATOR_STATUSES=()
ROUND_UPLOAD_STATUSES=()
ROUND_UPLOAD_BYTES=()
ROUND_UPLOAD_SECONDS=()
ROUND_UPLOAD_MIBPS=()
ROUND_DOWNLOAD_STATUSES=()
ROUND_DOWNLOAD_BYTES=()
ROUND_DOWNLOAD_SECONDS=()
ROUND_DOWNLOAD_MIBPS=()

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

log_event() {
  ((QUIET == 1)) && return 0
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

log_step() {
  CURRENT_STEP="$*"
  log_event "$*"
}

usage() {
  cat <<'EOF'
Usage:
  ./scp-speedtest.sh [alias-or-host] [options]
  ./scp-speedtest.sh --target <alias-or-host> [options]
  ./scp-speedtest.sh --host <host> [--user <user>] [options]

Description:
  Measure upload and download throughput with scp.
  Version: 1.0.2
  Authentication is handled by ssh/scp; this script does not store passwords.
  GitHub: https://github.com/cpiz/scp-speedtest

Options:
  --target <alias-or-host>       SSH config Host alias or hostname; can also be passed as a positional argument
  --host <host>                  Explicit SSH host or IP
  --user <user>                  Explicit SSH user
  --port <port>                  Explicit SSH port
  --identity-file <path>         SSH private key path
  --ssh-config <path>            SSH config file path
  --jump-host <host>             ProxyJump / -J host
  --connect-timeout <seconds>    SSH/SCP connection timeout in seconds
  --max-duration <seconds>       Per-transfer timeout for upload and download
  --rounds <count>               Number of test rounds, default 1
  --ssh-option <Key=Value>       Extra ssh/scp -o option; can be repeated
  --size <100M|1G>               Test file size, default 100M
  --remote-dir <path>            Remote test directory, defaults to remote mktemp -d
  --remote-file-method <method>  Remote file generator: auto, truncate, or dd
  --legacy-scp                   Enable legacy scp protocol with scp -O
  --json                         Print machine-readable JSON to stdout
  --keep                         Keep temporary files for troubleshooting
  --quiet                        Hide progress events and run scp in quiet mode
  --show-ssh-warnings            Show ssh/scp security warnings that are suppressed by default
  --dry-run                      Show resolved commands without running the test
  -h, --help                     Show help
  --version                      Show version

Examples:
  ./scp-speedtest.sh my-vps
  ./scp-speedtest.sh --target my-vps
  ./scp-speedtest.sh --host 1.2.3.4 --user root --port 2222 --identity-file ~/.ssh/id_ed25519
  ./scp-speedtest.sh my-vps --rounds 3
  ./scp-speedtest.sh my-vps --size 1G --json
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$option requires a value"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --target)
        require_value "$1" "${2:-}"
        TARGET="$2"
        shift 2
        ;;
      --host)
        require_value "$1" "${2:-}"
        HOST="$2"
        shift 2
        ;;
      --user)
        require_value "$1" "${2:-}"
        USER_NAME="$2"
        shift 2
        ;;
      --port)
        require_value "$1" "${2:-}"
        PORT="$2"
        shift 2
        ;;
      --identity-file)
        require_value "$1" "${2:-}"
        IDENTITY_FILE="$2"
        shift 2
        ;;
      --ssh-config)
        require_value "$1" "${2:-}"
        SSH_CONFIG="$2"
        shift 2
        ;;
      --jump-host)
        require_value "$1" "${2:-}"
        JUMP_HOST="$2"
        shift 2
        ;;
      --connect-timeout)
        require_value "$1" "${2:-}"
        CONNECT_TIMEOUT="$2"
        shift 2
        ;;
      --max-duration)
        require_value "$1" "${2:-}"
        MAX_DURATION="$2"
        shift 2
        ;;
      --rounds)
        require_value "$1" "${2:-}"
        ROUNDS="$2"
        shift 2
        ;;
      --ssh-option)
        require_value "$1" "${2:-}"
        SSH_OPTIONS+=("$2")
        shift 2
        ;;
      --size)
        require_value "$1" "${2:-}"
        SIZE="$2"
        shift 2
        ;;
      --remote-dir)
        require_value "$1" "${2:-}"
        REMOTE_DIR="$2"
        shift 2
        ;;
      --remote-file-method)
        require_value "$1" "${2:-}"
        REMOTE_FILE_METHOD="$2"
        shift 2
        ;;
      --legacy-scp)
        LEGACY_SCP=1
        shift
        ;;
      --json)
        JSON_OUTPUT=1
        shift
        ;;
      --keep)
        KEEP_FILES=1
        shift
        ;;
      --quiet)
        QUIET=1
        shift
        ;;
      --show-ssh-warnings)
        SHOW_SSH_WARNINGS=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "$VERSION"
        exit 0
        ;;
      --)
        shift
        while (($#)); do
          set_position_target "$1"
          shift
        done
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        set_position_target "$1"
        shift
        ;;
    esac
  done
}

set_position_target() {
  local value="$1"
  [[ -n "$value" ]] || die "positional alias-or-host cannot be empty"
  [[ -z "$POSITIONAL_TARGET" ]] || die "only one positional alias-or-host is allowed"
  POSITIONAL_TARGET="$value"
}

validate_args() {
  [[ -z "$TARGET" || -z "$POSITIONAL_TARGET" ]] || die "positional alias-or-host and --target cannot be used together"
  [[ -n "$HOST" || -n "$TARGET" || -n "$POSITIONAL_TARGET" ]] || die "provide alias-or-host, --target, or --host"

  if [[ -n "$PORT" && ! "$PORT" =~ ^[0-9]+$ ]]; then
    die "--port must be numeric"
  fi
  if [[ -n "$CONNECT_TIMEOUT" && ! "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]]; then
    die "--connect-timeout must be numeric"
  fi
  if [[ -n "$MAX_DURATION" && ! "$MAX_DURATION" =~ ^[0-9]+$ ]]; then
    die "--max-duration must be numeric"
  fi
  if [[ ! "$ROUNDS" =~ ^[0-9]+$ || "$ROUNDS" -lt 1 ]]; then
    die "--rounds must be a positive integer"
  fi
  case "$REMOTE_FILE_METHOD" in
    auto | truncate | dd) ;;
    *) die "--remote-file-method must be auto, truncate, or dd" ;;
  esac
  if [[ -n "$MAX_DURATION" ]] && ! command -v perl >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
    die "--max-duration requires perl or timeout"
  fi

  parse_size_to_bytes "$SIZE" >/dev/null
  SIZE_LABEL="$(normalize_size_label "$SIZE")"
  SIZE="$SIZE_LABEL"
  update_test_file_name
  build_remote_spec
}

build_remote_spec() {
  local host_part="$HOST"
  if [[ -z "$host_part" ]]; then
    host_part="${TARGET:-$POSITIONAL_TARGET}"
  fi

  [[ -n "$host_part" ]] || die "failed to determine remote host"

  if [[ -n "$USER_NAME" && "$host_part" != *@* ]]; then
    REMOTE_SPEC="${USER_NAME}@${host_part}"
  else
    REMOTE_SPEC="$host_part"
  fi
}

parse_size_to_bytes() {
  local raw="$1"
  local upper number suffix
  upper="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  if [[ "$upper" =~ ^([0-9]+)([KMG]?)(B?)$ ]]; then
    number="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
    case "$suffix" in
      K) printf '%s\n' $((number * 1024)) ;;
      M) printf '%s\n' $((number * 1024 * 1024)) ;;
      G) printf '%s\n' $((number * 1024 * 1024 * 1024)) ;;
      "") printf '%s\n' "$number" ;;
      *) die "unsupported size unit: ${raw}" ;;
    esac
  else
    die "invalid --size value: ${raw}. Examples: 100M, 1G, 1048576"
  fi
}

normalize_size_label() {
  local raw="$1"
  local upper number suffix
  upper="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  if [[ "$upper" =~ ^([0-9]+)([KMG]?)(B?)$ ]]; then
    number="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
    printf '%s%s\n' "$number" "$suffix"
  else
    die "invalid --size value: ${raw}. Examples: 100M, 1G, 1048576"
  fi
}

update_test_file_name() {
  TEST_FILE_NAME="scp-speedtest-${SIZE_LABEL}.bin"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

shell_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

format_remote_scp_path() {
  local path="$1"
  if ((LEGACY_SCP == 1)); then
    printf '%s:%s' "$REMOTE_SPEC" "$(shell_quote "$path")"
  else
    printf '%s:%s' "$REMOTE_SPEC" "$path"
  fi
}

make_local_tmp_dir() {
  local tmp_base="${TMPDIR:-/tmp}"
  tmp_base="${tmp_base%/}"
  mktemp -d "${tmp_base}/scp-speedtest.local.XXXXXX"
}

get_local_file_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    wc -c <"$file" | tr -d '[:space:]'
  else
    printf '0\n'
  fi
}

get_remote_file_size() {
  local file="$1"
  local output status quoted_file
  quoted_file="$(shell_quote "$file")"
  build_ssh_cmd

  set +e
  output="$("${SSH_CMD[@]}" "$REMOTE_SPEC" "if [ -f ${quoted_file} ]; then wc -c < ${quoted_file}; else printf '0\n'; fi" 2>/dev/null)"
  status=$?
  set -e

  if [[ "$status" -eq 0 && "$output" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$output"
  else
    printf '0\n'
  fi
}

run_scp_interruptible() {
  TRANSFER_INTERRUPTED=0
  LAST_SCP_STATUS=0
  trap 'TRANSFER_INTERRUPTED=1' INT

  set +e
  if [[ -n "$MAX_DURATION" ]] && command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$MAX_DURATION" "$@"
  elif [[ -n "$MAX_DURATION" ]] && command -v timeout >/dev/null 2>&1; then
    timeout "$MAX_DURATION" "$@"
  else
    "$@"
  fi
  LAST_SCP_STATUS=$?
  set -e

  trap - INT
  return 0
}

is_timeout_status() {
  [[ "$1" -eq 124 || "$1" -eq 142 ]]
}

now_seconds() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import time
print(f"{time.time():.6f}")
PY
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.6f\n", time'
  else
    date +%s
  fi
}

calc_duration() {
  local start="$1"
  local end="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$start" "$end" <<'PY'
import sys
start = float(sys.argv[1])
end = float(sys.argv[2])
print(f"{max(end - start, 0.000001):.6f}")
PY
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'printf "%.6f\n", ($ARGV[1] - $ARGV[0]) > 0 ? ($ARGV[1] - $ARGV[0]) : 0.000001' "$start" "$end"
  else
    local diff=$((end - start))
    ((diff > 0)) || diff=1
    printf '%s\n' "$diff"
  fi
}

calc_mibps() {
  local bytes="$1"
  local seconds="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$bytes" "$seconds" <<'PY'
import sys
bytes_count = int(sys.argv[1])
seconds = float(sys.argv[2])
print(f"{bytes_count / 1024 / 1024 / seconds:.2f}")
PY
  else
    awk -v bytes="$bytes" -v seconds="$seconds" 'BEGIN { printf "%.2f", bytes / 1024 / 1024 / seconds }'
  fi
}

calc_total_seconds() {
  if (($# == 0)); then
    printf '0.000000\n'
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$@" <<'PY'
import sys
print(f"{sum(float(v) for v in sys.argv[1:]):.6f}")
PY
  elif command -v perl >/dev/null 2>&1; then
    perl -e '$sum = 0; $sum += $_ for @ARGV; printf "%.6f\n", $sum' "$@"
  else
    awk 'BEGIN { for (i = 1; i < ARGC; i++) sum += ARGV[i]; printf "%.6f\n", sum }' "$@"
  fi
}

calc_average_completed_mibps() {
  local count="$1"
  local bytes="$2"
  local seconds="$3"
  if ((count == 0)); then
    printf '0.00\n'
    return 0
  fi
  calc_mibps $((count * bytes)) "$seconds"
}

has_ssh_option_key() {
  local wanted="$1"
  local opt key
  wanted="$(printf '%s' "$wanted" | tr '[:upper:]' '[:lower:]')"

  for opt in "${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"}"; do
    key="${opt%%=*}"
    key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
    [[ "$key" == "$wanted" ]] && return 0
  done

  return 1
}

ssh_supports_warn_weak_crypto() {
  if [[ -n "$WARN_WEAK_CRYPTO_SUPPORTED" ]]; then
    [[ "$WARN_WEAK_CRYPTO_SUPPORTED" == "1" ]]
    return
  fi

  if ssh -F /dev/null -G -o WarnWeakCrypto=no __scp_speedtest_probe__ >/dev/null 2>&1; then
    WARN_WEAK_CRYPTO_SUPPORTED=1
  else
    WARN_WEAK_CRYPTO_SUPPORTED=0
  fi

  [[ "$WARN_WEAK_CRYPTO_SUPPORTED" == "1" ]]
}

should_suppress_ssh_warnings() {
  ((SHOW_SSH_WARNINGS == 0)) || return 1
  has_ssh_option_key "WarnWeakCrypto" && return 1
  ssh_supports_warn_weak_crypto
}

build_ssh_cmd() {
  SSH_CMD=(ssh)
  [[ -z "$SSH_CONFIG" ]] || SSH_CMD+=(-F "$SSH_CONFIG")
  [[ -z "$PORT" ]] || SSH_CMD+=(-p "$PORT")
  [[ -z "$IDENTITY_FILE" ]] || SSH_CMD+=(-i "$IDENTITY_FILE")
  [[ -z "$JUMP_HOST" ]] || SSH_CMD+=(-J "$JUMP_HOST")
  [[ -z "$CONNECT_TIMEOUT" ]] || SSH_CMD+=(-o "ConnectTimeout=${CONNECT_TIMEOUT}")
  should_suppress_ssh_warnings && SSH_CMD+=(-o "WarnWeakCrypto=no")
  local opt
  for opt in "${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"}"; do
    SSH_CMD+=(-o "$opt")
  done
}

build_scp_cmd() {
  SCP_CMD=(scp)
  ((QUIET == 0)) || SCP_CMD+=(-q)
  ((LEGACY_SCP == 0)) || SCP_CMD+=(-O)
  [[ -z "$SSH_CONFIG" ]] || SCP_CMD+=(-F "$SSH_CONFIG")
  [[ -z "$PORT" ]] || SCP_CMD+=(-P "$PORT")
  [[ -z "$IDENTITY_FILE" ]] || SCP_CMD+=(-i "$IDENTITY_FILE")
  [[ -z "$JUMP_HOST" ]] || SCP_CMD+=(-J "$JUMP_HOST")
  [[ -z "$CONNECT_TIMEOUT" ]] || SCP_CMD+=(-o "ConnectTimeout=${CONNECT_TIMEOUT}")
  should_suppress_ssh_warnings && SCP_CMD+=(-o "WarnWeakCrypto=no")
  local opt
  for opt in "${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"}"; do
    SCP_CMD+=(-o "$opt")
  done
}

command_to_string() {
  local -a parts=("$@")
  local item
  local out=""
  for item in "${parts[@]}"; do
    if [[ -z "$out" ]]; then
      printf -v out '%q' "$item"
    else
      printf -v out '%s %q' "$out" "$item"
    fi
  done
  printf '%s' "$out"
}

checksum_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    die "shasum or sha256sum is required to verify the downloaded file"
  fi
}

generate_test_file() {
  local file="$1"
  local bytes="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$bytes" <<'PY'
import os
import sys
path = sys.argv[1]
size = int(sys.argv[2])
with open(path, "wb") as f:
    f.truncate(size)
PY
  else
    dd if=/dev/zero of="$file" bs=1048576 count=$((bytes / 1048576)) status=none
    local remainder=$((bytes % 1048576))
    if ((remainder > 0)); then
      dd if=/dev/zero bs="$remainder" count=1 status=none >>"$file"
    fi
  fi
}

generate_remote_test_file() {
  local file="$1"
  local bytes="$2"
  local quoted_file mb remainder remote_script
  quoted_file="$(shell_quote "$file")"
  mb=$((bytes / 1048576))
  remainder=$((bytes % 1048576))
  build_ssh_cmd

  case "$REMOTE_FILE_METHOD" in
    auto)
      remote_script="if command -v truncate >/dev/null 2>&1; then truncate -s ${bytes} ${quoted_file} && printf 'truncate\n'; else dd if=/dev/zero of=${quoted_file} bs=1048576 count=${mb} >/dev/null 2>&1; if [ ${remainder} -gt 0 ]; then dd if=/dev/zero bs=${remainder} count=1 >> ${quoted_file} 2>/dev/null; fi; printf 'dd\n'; fi"
      ;;
    truncate)
      remote_script="if command -v truncate >/dev/null 2>&1; then truncate -s ${bytes} ${quoted_file} && printf 'truncate\n'; else printf 'truncate is not available on remote host\n' >&2; exit 127; fi"
      ;;
    dd)
      remote_script="dd if=/dev/zero of=${quoted_file} bs=1048576 count=${mb} >/dev/null 2>&1; if [ ${remainder} -gt 0 ]; then dd if=/dev/zero bs=${remainder} count=1 >> ${quoted_file} 2>/dev/null; fi; printf 'dd\n'"
      ;;
  esac
  REMOTE_GENERATOR="$("${SSH_CMD[@]}" "$REMOTE_SPEC" "$remote_script")"
  REMOTE_GENERATOR_STATUS="completed"
}

prepare_remote_dir() {
  build_ssh_cmd

  if [[ -n "$REMOTE_DIR" ]]; then
    log_step "Connecting and preparing remote directory: ${REMOTE_SPEC}:${REMOTE_DIR}"
    "${SSH_CMD[@]}" "$REMOTE_SPEC" "mkdir -p -- $(shell_quote "$REMOTE_DIR")"
    REMOTE_TMP_DIR="$REMOTE_DIR"
    REMOTE_TMP_CREATED=0
    log_event "Remote directory ready: ${REMOTE_DIR}"
  else
    log_step "Connecting and creating remote temporary directory: ${REMOTE_SPEC}"
    # shellcheck disable=SC2016
    REMOTE_TMP_DIR="$("${SSH_CMD[@]}" "$REMOTE_SPEC" 'tmp_base="${TMPDIR:-/tmp}"; tmp_base="${tmp_base%/}"; mktemp -d "${tmp_base}/scp-speedtest.XXXXXX"')"
    [[ -n "$REMOTE_TMP_DIR" ]] || die "failed to create remote temporary directory"
    REMOTE_TMP_CREATED=1
    log_event "Remote temporary directory created: ${REMOTE_TMP_DIR}"
  fi
}

cleanup() {
  local exit_code=$?
  if ((KEEP_FILES == 0)); then
    if [[ -n "$LOCAL_TMP_DIR" && -d "$LOCAL_TMP_DIR" ]]; then
      log_event "Cleaning local temporary directory: ${LOCAL_TMP_DIR}"
      rm -rf "$LOCAL_TMP_DIR"
    fi
    if [[ -n "$REMOTE_SPEC" && -n "$REMOTE_TEST_FILE" ]]; then
      log_event "Cleaning remote test file: ${REMOTE_SPEC}:${REMOTE_TEST_FILE}"
      build_ssh_cmd
      "${SSH_CMD[@]}" "$REMOTE_SPEC" "rm -f -- $(shell_quote "$REMOTE_TEST_FILE")" >/dev/null 2>&1 || true
    fi
    if [[ -n "$REMOTE_SPEC" && -n "$REMOTE_TMP_DIR" && $REMOTE_TMP_CREATED -eq 1 ]]; then
      log_event "Cleaning remote temporary directory: ${REMOTE_SPEC}:${REMOTE_TMP_DIR}"
      build_ssh_cmd
      "${SSH_CMD[@]}" "$REMOTE_SPEC" "rm -rf -- $(shell_quote "$REMOTE_TMP_DIR")" >/dev/null 2>&1 || true
    fi
  else
    [[ -z "$LOCAL_TMP_DIR" ]] || printf 'Kept local temporary directory: %s\n' "$LOCAL_TMP_DIR" >&2
    [[ -z "$REMOTE_TMP_DIR" ]] || printf 'Kept remote temporary directory: %s\n' "$REMOTE_TMP_DIR" >&2
  fi
  if [[ "$exit_code" -ne 0 && "$ERROR_CARD_PRINTED" -eq 0 && -n "$REMOTE_SPEC" ]]; then
    if ((JSON_OUTPUT == 1)); then
      print_json_error_result "$exit_code"
    else
      print_error_result "$exit_code" >&2
    fi
    ERROR_CARD_PRINTED=1
  fi
  return "$exit_code"
}

status_label() {
  case "$1" in
    completed) printf 'completed' ;;
    interrupted) printf 'interrupted' ;;
    timeout) printf 'timeout' ;;
    partial) printf 'completed (partial file)' ;;
    skipped) printf 'skipped' ;;
    *) printf '%s' "$1" ;;
  esac
}

supports_style() {
  [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]
}

style_text() {
  local code="$1"
  local text="$2"
  if supports_style; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

status_badge() {
  local status="$1"
  local label
  label="$(printf '%s' "$(status_label "$status")" | tr '[:lower:]' '[:upper:]')"
  case "$status" in
    completed) style_text "1;32" "$label" ;;
    interrupted) style_text "1;33" "$label" ;;
    timeout) style_text "1;31" "$label" ;;
    *) style_text "1" "$label" ;;
  esac
}

format_mib() {
  local bytes="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$bytes" <<'PY'
import sys
print(f"{int(sys.argv[1]) / 1024 / 1024:.2f}")
PY
  else
    awk -v bytes="$bytes" 'BEGIN { printf "%.2f", bytes / 1024 / 1024 }'
  fi
}

print_result_rule() {
  printf '%s\n' '======================================================================'
}

print_transfer_line() {
  local label="$1"
  local status="$2"
  local transferred_bytes="$3"
  local total_bytes="$4"
  local seconds="$5"
  local mibps="$6"
  local transferred_mib total_mib
  transferred_mib="$(format_mib "$transferred_bytes")"
  total_mib="$(format_mib "$total_bytes")"

  printf '%-9s: %-12s %9s / %-9s MiB  %10s s  %8s MiB/s\n' \
    "$label" "$(status_badge "$status")" "$transferred_mib" "$total_mib" "$seconds" "$mibps"
}

print_human_result() {
  local bytes="$1"

  print_result_rule
  printf '%s\n' "$(style_text "1" "scp-speedtest result")"
  printf 'GitHub   : %s\n' "$PROJECT_URL"
  printf 'Target   : %s\n' "$REMOTE_SPEC"
  printf 'Test file: %s (%s MiB / %s bytes)\n' "$TEST_FILE_NAME" "$(format_mib "$bytes")" "$bytes"
  printf '%s\n' '----------------------------------------------------------------------'
  print_transfer_line "Upload" "$UPLOAD_STATUS" "$UPLOAD_BYTES" "$bytes" "$UPLOAD_SECONDS" "$UPLOAD_MIBPS"
  print_transfer_line "Download" "$DOWNLOAD_STATUS" "$DOWNLOAD_BYTES" "$bytes" "$DOWNLOAD_SECONDS" "$DOWNLOAD_MIBPS"
  print_result_rule
}

print_human_summary() {
  local bytes="$1"
  local upload_completed=0
  local download_completed=0
  local upload_seconds_values=()
  local download_seconds_values=()
  local upload_total_seconds download_total_seconds
  local upload_avg download_avg
  local i

  for ((i = 0; i < ROUNDS; i++)); do
    if [[ "${ROUND_UPLOAD_STATUSES[$i]}" == "completed" ]]; then
      upload_completed=$((upload_completed + 1))
      upload_seconds_values+=("${ROUND_UPLOAD_SECONDS[$i]}")
    fi
    if [[ "${ROUND_DOWNLOAD_STATUSES[$i]}" == "completed" ]]; then
      download_completed=$((download_completed + 1))
      download_seconds_values+=("${ROUND_DOWNLOAD_SECONDS[$i]}")
    fi
  done

  upload_total_seconds="$(calc_total_seconds "${upload_seconds_values[@]+"${upload_seconds_values[@]}"}")"
  download_total_seconds="$(calc_total_seconds "${download_seconds_values[@]+"${download_seconds_values[@]}"}")"
  upload_avg="$(calc_average_completed_mibps "$upload_completed" "$bytes" "$upload_total_seconds")"
  download_avg="$(calc_average_completed_mibps "$download_completed" "$bytes" "$download_total_seconds")"

  print_result_rule
  printf '%s\n' "$(style_text "1" "scp-speedtest summary")"
  printf 'GitHub          : %s\n' "$PROJECT_URL"
  printf 'Target          : %s\n' "$REMOTE_SPEC"
  printf 'Rounds          : %s\n' "$ROUNDS"
  printf 'Test file       : %s (%s MiB / %s bytes)\n' "$TEST_FILE_NAME" "$(format_mib "$bytes")" "$bytes"
  printf '%s\n' '----------------------------------------------------------------------'
  printf 'Upload average  : %s MiB/s (%s/%s completed rounds)\n' "$upload_avg" "$upload_completed" "$ROUNDS"
  printf 'Download average: %s MiB/s (%s/%s completed rounds)\n' "$download_avg" "$download_completed" "$ROUNDS"
  print_result_rule
}

print_error_result() {
  local exit_code="$1"
  print_result_rule
  printf '%s\n' "$(style_text "1;31" "scp-speedtest failed")"
  printf 'GitHub   : %s\n' "$PROJECT_URL"
  printf 'Target   : %s\n' "$REMOTE_SPEC"
  [[ -z "$TEST_FILE_NAME" ]] || printf 'Test file: %s\n' "$TEST_FILE_NAME"
  [[ -z "$CURRENT_STEP" ]] || printf 'Step     : %s\n' "$CURRENT_STEP"
  printf 'Exit code: %s\n' "$exit_code"
  printf '%s\n' '----------------------------------------------------------------------'
  printf '%s\n' 'The underlying ssh/scp error is shown above.'
  printf '%s\n' 'Use --dry-run to inspect resolved commands without connecting.'
  print_result_rule
}

print_json_error_result() {
  local exit_code="$1"
  local started_at="$STARTED_AT"
  local ended_at="$ENDED_AT"
  [[ -n "$ended_at" ]] || ended_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  printf '{'
  printf '"ok":false,'
  printf '"version":"%s",' "$(json_escape "$VERSION")"
  printf '"target":"%s",' "$(json_escape "$REMOTE_SPEC")"
  printf '"size":"%s",' "$(json_escape "$SIZE")"
  printf '"test_file":"%s",' "$(json_escape "$TEST_FILE_NAME")"
  printf '"bytes":%s,' "$TEST_BYTES"
  printf '"started_at":"%s",' "$(json_escape "$started_at")"
  printf '"ended_at":"%s",' "$(json_escape "$ended_at")"
  printf '"error":{'
  printf '"step":"%s",' "$(json_escape "$CURRENT_STEP")"
  printf '"exit_code":%s,' "$exit_code"
  printf '"message":"%s"' "$(json_escape "runtime command failed; see stderr for ssh/scp details")"
  printf '}'
  printf '}\n'
}

print_json_result() {
  local bytes="$1"

  printf '{'
  printf '"ok":%s,' "$([[ "$DOWNLOAD_STATUS" == "completed" ]] && printf true || printf false)"
  printf '"version":"%s",' "$(json_escape "$VERSION")"
  printf '"target":"%s",' "$(json_escape "$REMOTE_SPEC")"
  printf '"size":"%s",' "$(json_escape "$SIZE")"
  printf '"test_file":"%s",' "$(json_escape "$TEST_FILE_NAME")"
  printf '"bytes":%s,' "$bytes"
  printf '"started_at":"%s",' "$(json_escape "$STARTED_AT")"
  printf '"ended_at":"%s",' "$(json_escape "$ENDED_AT")"
  printf '"remote_dir":"%s",' "$(json_escape "$REMOTE_TMP_DIR")"
  printf '"remote_generator":{"status":"%s","method":"%s"},' "$(json_escape "$REMOTE_GENERATOR_STATUS")" "$(json_escape "$REMOTE_GENERATOR")"
  printf '"upload":{"status":"%s","bytes":%s,"seconds":%s,"mib_per_second":%s},' "$(json_escape "$UPLOAD_STATUS")" "$UPLOAD_BYTES" "$UPLOAD_SECONDS" "$UPLOAD_MIBPS"
  printf '"download":{"status":"%s","bytes":%s,"seconds":%s,"mib_per_second":%s}' "$(json_escape "$DOWNLOAD_STATUS")" "$DOWNLOAD_BYTES" "$DOWNLOAD_SECONDS" "$DOWNLOAD_MIBPS"
  printf '}\n'
}

print_json_multi_result() {
  local bytes="$1"
  local upload_completed=0
  local download_completed=0
  local upload_seconds_values=()
  local download_seconds_values=()
  local upload_total_seconds download_total_seconds
  local upload_avg download_avg
  local ok=true
  local i

  for ((i = 0; i < ROUNDS; i++)); do
    if [[ "${ROUND_UPLOAD_STATUSES[$i]}" == "completed" ]]; then
      upload_completed=$((upload_completed + 1))
      upload_seconds_values+=("${ROUND_UPLOAD_SECONDS[$i]}")
    fi
    if [[ "${ROUND_DOWNLOAD_STATUSES[$i]}" == "completed" ]]; then
      download_completed=$((download_completed + 1))
      download_seconds_values+=("${ROUND_DOWNLOAD_SECONDS[$i]}")
    else
      ok=false
    fi
  done

  upload_total_seconds="$(calc_total_seconds "${upload_seconds_values[@]+"${upload_seconds_values[@]}"}")"
  download_total_seconds="$(calc_total_seconds "${download_seconds_values[@]+"${download_seconds_values[@]}"}")"
  upload_avg="$(calc_average_completed_mibps "$upload_completed" "$bytes" "$upload_total_seconds")"
  download_avg="$(calc_average_completed_mibps "$download_completed" "$bytes" "$download_total_seconds")"

  printf '{'
  printf '"ok":%s,' "$ok"
  printf '"version":"%s",' "$(json_escape "$VERSION")"
  printf '"target":"%s",' "$(json_escape "$REMOTE_SPEC")"
  printf '"size":"%s",' "$(json_escape "$SIZE")"
  printf '"test_file":"%s",' "$(json_escape "$TEST_FILE_NAME")"
  printf '"bytes":%s,' "$bytes"
  printf '"round_count":%s,' "$ROUNDS"
  printf '"started_at":"%s",' "$(json_escape "${ROUND_STARTED_ATS[0]}")"
  printf '"ended_at":"%s",' "$(json_escape "${ROUND_ENDED_ATS[$((ROUNDS - 1))]}")"
  printf '"rounds":['
  for ((i = 0; i < ROUNDS; i++)); do
    ((i == 0)) || printf ','
    printf '{'
    printf '"round":%s,' "$((i + 1))"
    printf '"started_at":"%s",' "$(json_escape "${ROUND_STARTED_ATS[$i]}")"
    printf '"ended_at":"%s",' "$(json_escape "${ROUND_ENDED_ATS[$i]}")"
    printf '"remote_dir":"%s",' "$(json_escape "${ROUND_REMOTE_DIRS[$i]}")"
    printf '"remote_generator":{"status":"%s","method":"%s"},' "$(json_escape "${ROUND_REMOTE_GENERATOR_STATUSES[$i]}")" "$(json_escape "${ROUND_REMOTE_GENERATORS[$i]}")"
    printf '"upload":{"status":"%s","bytes":%s,"seconds":%s,"mib_per_second":%s},' "$(json_escape "${ROUND_UPLOAD_STATUSES[$i]}")" "${ROUND_UPLOAD_BYTES[$i]}" "${ROUND_UPLOAD_SECONDS[$i]}" "${ROUND_UPLOAD_MIBPS[$i]}"
    printf '"download":{"status":"%s","bytes":%s,"seconds":%s,"mib_per_second":%s}' "$(json_escape "${ROUND_DOWNLOAD_STATUSES[$i]}")" "${ROUND_DOWNLOAD_BYTES[$i]}" "${ROUND_DOWNLOAD_SECONDS[$i]}" "${ROUND_DOWNLOAD_MIBPS[$i]}"
    printf '}'
  done
  printf '],'
  printf '"summary":{'
  printf '"upload":{"completed_rounds":%s,"average_mib_per_second":%s},' "$upload_completed" "$upload_avg"
  printf '"download":{"completed_rounds":%s,"average_mib_per_second":%s}' "$download_completed" "$download_avg"
  printf '}'
  printf '}\n'
}

reset_round_state() {
  LOCAL_TMP_DIR=""
  LOCAL_DOWNLOAD_DIR=""
  REMOTE_TMP_DIR=""
  REMOTE_TMP_CREATED=0
  REMOTE_TEST_FILE=""
  TRANSFER_INTERRUPTED=0
  LAST_SCP_STATUS=0
  UPLOAD_STATUS="skipped"
  UPLOAD_BYTES=0
  UPLOAD_SECONDS="0.000000"
  UPLOAD_MIBPS="0.00"
  DOWNLOAD_STATUS="skipped"
  DOWNLOAD_BYTES=0
  DOWNLOAD_SECONDS="0.000000"
  DOWNLOAD_MIBPS="0.00"
  STARTED_AT=""
  ENDED_AT=""
  REMOTE_GENERATOR=""
  REMOTE_GENERATOR_STATUS="skipped"
  CURRENT_STEP=""
}

collect_round_result() {
  ROUND_STARTED_ATS+=("$STARTED_AT")
  ROUND_ENDED_ATS+=("$ENDED_AT")
  ROUND_REMOTE_DIRS+=("$REMOTE_TMP_DIR")
  ROUND_REMOTE_GENERATORS+=("$REMOTE_GENERATOR")
  ROUND_REMOTE_GENERATOR_STATUSES+=("$REMOTE_GENERATOR_STATUS")
  ROUND_UPLOAD_STATUSES+=("$UPLOAD_STATUS")
  ROUND_UPLOAD_BYTES+=("$UPLOAD_BYTES")
  ROUND_UPLOAD_SECONDS+=("$UPLOAD_SECONDS")
  ROUND_UPLOAD_MIBPS+=("$UPLOAD_MIBPS")
  ROUND_DOWNLOAD_STATUSES+=("$DOWNLOAD_STATUS")
  ROUND_DOWNLOAD_BYTES+=("$DOWNLOAD_BYTES")
  ROUND_DOWNLOAD_SECONDS+=("$DOWNLOAD_SECONDS")
  ROUND_DOWNLOAD_MIBPS+=("$DOWNLOAD_MIBPS")
}

print_round_human_result() {
  local bytes="$1"
  if ((ROUNDS > 1)); then
    printf 'Round %s/%s:\n' "$ROUND_INDEX" "$ROUNDS"
  fi
  print_human_result "$bytes"
}

print_dry_run() {
  local bytes="$1"
  build_ssh_cmd
  build_scp_cmd

  if ((JSON_OUTPUT == 1)); then
    printf '{'
    printf '"target":"%s",' "$(json_escape "$REMOTE_SPEC")"
    printf '"size":"%s",' "$(json_escape "$SIZE")"
    printf '"test_file":"%s",' "$(json_escape "$TEST_FILE_NAME")"
    printf '"bytes":%s,' "$bytes"
    printf '"rounds":%s,' "$ROUNDS"
    printf '"remote_file_method":"%s",' "$(json_escape "$REMOTE_FILE_METHOD")"
    printf '"ssh_command":"%s",' "$(json_escape "$(command_to_string "${SSH_CMD[@]}" "$REMOTE_SPEC")")"
    printf '"scp_command":"%s"' "$(json_escape "$(command_to_string "${SCP_CMD[@]}")")"
    printf '}\n'
  else
    printf 'Target: %s\n' "$REMOTE_SPEC"
    printf 'Test file: %s (%s bytes)\n' "$TEST_FILE_NAME" "$bytes"
    printf 'Rounds: %s\n' "$ROUNDS"
    printf 'Remote file method: %s\n' "$REMOTE_FILE_METHOD"
    printf 'SSH command: %s\n' "$(command_to_string "${SSH_CMD[@]}" "$REMOTE_SPEC")"
    printf 'SCP command: %s\n' "$(command_to_string "${SCP_CMD[@]}")"
  fi
}

run_speedtest() {
  local bytes="$1"
  local local_file download_file
  local upload_start upload_end
  local download_start download_end
  local source_hash download_hash

  STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  LOCAL_TMP_DIR="$(make_local_tmp_dir)"
  local_file="${LOCAL_TMP_DIR}/${TEST_FILE_NAME}"
  LOCAL_DOWNLOAD_DIR="${LOCAL_TMP_DIR}/download"
  mkdir -p "$LOCAL_DOWNLOAD_DIR"
  download_file="${LOCAL_DOWNLOAD_DIR}/${TEST_FILE_NAME}"

  if ((ROUNDS > 1)); then
    log_event "Round ${ROUND_INDEX}/${ROUNDS}"
  fi
  log_step "Target: ${REMOTE_SPEC}"
  log_step "Creating local test file: ${local_file} (${SIZE} / ${bytes} bytes)"
  generate_test_file "$local_file" "$bytes"
  log_step "Local test file created; calculating source checksum"
  source_hash="$(checksum_file "$local_file")"

  prepare_remote_dir
  REMOTE_TEST_FILE="${REMOTE_TMP_DIR}/${TEST_FILE_NAME}"

  build_scp_cmd

  log_step "Starting upload: ${local_file} -> $(format_remote_scp_path "$REMOTE_TEST_FILE")"
  upload_start="$(now_seconds)"
  run_scp_interruptible "${SCP_CMD[@]}" "$local_file" "$(format_remote_scp_path "$REMOTE_TEST_FILE")"
  upload_end="$(now_seconds)"
  UPLOAD_SECONDS="$(calc_duration "$upload_start" "$upload_end")"

  if [[ "$LAST_SCP_STATUS" -eq 0 ]]; then
    UPLOAD_STATUS="completed"
    UPLOAD_BYTES="$bytes"
  elif [[ "$TRANSFER_INTERRUPTED" -eq 1 || "$LAST_SCP_STATUS" -eq 130 ]]; then
    UPLOAD_STATUS="interrupted"
    UPLOAD_BYTES="$(get_remote_file_size "$REMOTE_TEST_FILE")"
    log_event "Upload interrupted; recorded remote file size: ${UPLOAD_BYTES} bytes"
  elif [[ -n "$MAX_DURATION" ]] && is_timeout_status "$LAST_SCP_STATUS"; then
    UPLOAD_STATUS="timeout"
    UPLOAD_BYTES="$(get_remote_file_size "$REMOTE_TEST_FILE")"
    log_event "Upload timed out; recorded remote file size: ${UPLOAD_BYTES} bytes"
  else
    die "upload failed with scp exit code: ${LAST_SCP_STATUS}"
  fi

  UPLOAD_MIBPS="$(calc_mibps "$UPLOAD_BYTES" "$UPLOAD_SECONDS")"
  log_event "Upload $(status_label "$UPLOAD_STATUS"): ${UPLOAD_BYTES} bytes, ${UPLOAD_SECONDS} seconds, ${UPLOAD_MIBPS} MiB/s"

  log_step "Preparing remote download test file: ${REMOTE_SPEC}:${REMOTE_TEST_FILE} (${SIZE} / ${bytes} bytes)"
  build_ssh_cmd
  "${SSH_CMD[@]}" "$REMOTE_SPEC" "rm -f -- $(shell_quote "$REMOTE_TEST_FILE")"
  generate_remote_test_file "$REMOTE_TEST_FILE" "$bytes"
  log_event "Remote download test file ready (method: ${REMOTE_GENERATOR})"

  log_step "Starting download: $(format_remote_scp_path "$REMOTE_TEST_FILE") -> ${download_file}"
  download_start="$(now_seconds)"
  run_scp_interruptible "${SCP_CMD[@]}" "$(format_remote_scp_path "$REMOTE_TEST_FILE")" "$download_file"
  download_end="$(now_seconds)"
  DOWNLOAD_SECONDS="$(calc_duration "$download_start" "$download_end")"

  if [[ "$LAST_SCP_STATUS" -eq 0 ]]; then
    DOWNLOAD_STATUS="completed"
    DOWNLOAD_BYTES="$(get_local_file_size "$download_file")"
  elif [[ "$TRANSFER_INTERRUPTED" -eq 1 || "$LAST_SCP_STATUS" -eq 130 ]]; then
    DOWNLOAD_STATUS="interrupted"
    DOWNLOAD_BYTES="$(get_local_file_size "$download_file")"
    log_event "Download interrupted; recorded local file size: ${DOWNLOAD_BYTES} bytes"
  elif [[ -n "$MAX_DURATION" ]] && is_timeout_status "$LAST_SCP_STATUS"; then
    DOWNLOAD_STATUS="timeout"
    DOWNLOAD_BYTES="$(get_local_file_size "$download_file")"
    log_event "Download timed out; recorded local file size: ${DOWNLOAD_BYTES} bytes"
  else
    die "download failed with scp exit code: ${LAST_SCP_STATUS}"
  fi

  DOWNLOAD_MIBPS="$(calc_mibps "$DOWNLOAD_BYTES" "$DOWNLOAD_SECONDS")"
  log_event "Download $(status_label "$DOWNLOAD_STATUS"): ${DOWNLOAD_BYTES} bytes, ${DOWNLOAD_SECONDS} seconds, ${DOWNLOAD_MIBPS} MiB/s"

  if [[ "$DOWNLOAD_STATUS" == "completed" && "$DOWNLOAD_BYTES" -eq "$bytes" ]]; then
    log_step "Verifying downloaded file checksum"
    download_hash="$(checksum_file "$download_file")"
    [[ "$source_hash" == "$download_hash" ]] || die "downloaded file checksum verification failed"
    log_event "Checksum verification passed"
  else
    log_event "Skipping checksum verification because transfer was interrupted or partial"
  fi

  ENDED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

}

run_speedtest_rounds() {
  local bytes="$1"

  for ((ROUND_INDEX = 1; ROUND_INDEX <= ROUNDS; ROUND_INDEX++)); do
    reset_round_state
    run_speedtest "$bytes"
    collect_round_result
    cleanup

    if ((JSON_OUTPUT == 0)); then
      print_round_human_result "$bytes"
    fi

    reset_round_state
  done

  if ((JSON_OUTPUT == 1)); then
    if ((ROUNDS == 1)); then
      STARTED_AT="${ROUND_STARTED_ATS[0]}"
      ENDED_AT="${ROUND_ENDED_ATS[0]}"
      REMOTE_TMP_DIR="${ROUND_REMOTE_DIRS[0]}"
      REMOTE_GENERATOR="${ROUND_REMOTE_GENERATORS[0]}"
      REMOTE_GENERATOR_STATUS="${ROUND_REMOTE_GENERATOR_STATUSES[0]}"
      UPLOAD_STATUS="${ROUND_UPLOAD_STATUSES[0]}"
      UPLOAD_BYTES="${ROUND_UPLOAD_BYTES[0]}"
      UPLOAD_SECONDS="${ROUND_UPLOAD_SECONDS[0]}"
      UPLOAD_MIBPS="${ROUND_UPLOAD_MIBPS[0]}"
      DOWNLOAD_STATUS="${ROUND_DOWNLOAD_STATUSES[0]}"
      DOWNLOAD_BYTES="${ROUND_DOWNLOAD_BYTES[0]}"
      DOWNLOAD_SECONDS="${ROUND_DOWNLOAD_SECONDS[0]}"
      DOWNLOAD_MIBPS="${ROUND_DOWNLOAD_MIBPS[0]}"
      print_json_result "$bytes"
      reset_round_state
    else
      print_json_multi_result "$bytes"
    fi
  elif ((ROUNDS > 1)); then
    print_human_summary "$bytes"
  fi
}

main() {
  if (($# == 0)); then
    usage
    return 0
  fi

  parse_args "$@"
  validate_args

  local bytes
  bytes="$(parse_size_to_bytes "$SIZE")"
  TEST_BYTES="$bytes"

  if ((DRY_RUN == 1)); then
    print_dry_run "$bytes"
    return 0
  fi

  trap cleanup EXIT
  run_speedtest_rounds "$bytes"
}

if [[ "${BASH_SOURCE[0]-}" == "$0" || -z "${BASH_SOURCE[0]-}" ]]; then
  main "$@"
fi
