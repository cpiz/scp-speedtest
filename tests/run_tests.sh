#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scp-speedtest.sh"

PASS_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %d - %s\n' "$PASS_COUNT" "$*"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "${message}. Missing: ${needle}. Output: ${haystack}"
  pass "$message"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "${message}. Should not contain: ${needle}. Output: ${haystack}"
  pass "$message"
}

assert_fails_contains() {
  local message="$1"
  local needle="$2"
  shift 2

  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "${message}. Command should fail but succeeded. Output: ${output}"
  assert_contains "$output" "$needle" "$message"
}

test_no_arguments_prints_help() {
  local output status
  set +e
  output="$(bash "$SCRIPT" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "no arguments should print help and exit 0. Status: ${status}. Output: ${output}"
  assert_contains "$output" "Usage:" "no arguments prints usage"
  assert_contains "$output" "Options:" "no arguments prints options"
  assert_contains "$output" "Examples:" "no arguments prints examples"
}

test_default_size_and_positional_target() {
  local output
  output="$(bash "$SCRIPT" my-vps --dry-run)"

  assert_contains "$output" "Target: my-vps" "positional target is accepted"
  assert_contains "$output" "Test file: scp-speedtest-100M.bin (104857600 bytes)" "default test file name includes 100M"
  assert_contains "$output" "SSH command: ssh my-vps" "default SSH command uses alias"
  assert_contains "$output" "SCP command: scp" "default SCP command is not quiet"
  assert_not_contains "$output" "SCP command: scp -q" "default SCP command allows progress output"
}

test_target_option() {
  local output
  output="$(bash "$SCRIPT" --target my-vps --dry-run)"

  assert_contains "$output" "Target: my-vps" "--target is accepted"
  assert_contains "$output" "Test file: scp-speedtest-100M.bin (104857600 bytes)" "--target keeps default test file size"
}

test_size_specific_filename() {
  local output
  output="$(bash "$SCRIPT" my-vps --size 1G --dry-run)"

  assert_contains "$output" "Test file: scp-speedtest-1G.bin (1073741824 bytes)" "test file name includes requested size"
}

test_explicit_connection_options() {
  local output
  output="$(bash "$SCRIPT" \
    --host 1.2.3.4 \
    --user root \
    --port 2222 \
    --identity-file /tmp/id_ed25519 \
    --ssh-config /tmp/ssh_config \
    --jump-host jump-box \
    --ssh-option StrictHostKeyChecking=no \
    --legacy-scp \
    --dry-run)"

  assert_contains "$output" "Target: root@1.2.3.4" "explicit user and host build remote target"
  assert_contains "$output" "SSH command: ssh" "prints SSH command"
  assert_contains "$output" "-F /tmp/ssh_config" "SSH/SCP includes config path"
  assert_contains "$output" "-p 2222" "SSH uses lowercase -p port"
  assert_contains "$output" "-P 2222" "SCP uses uppercase -P port"
  assert_contains "$output" "-i /tmp/id_ed25519" "includes identity file"
  assert_contains "$output" "-J jump-box" "includes jump host"
  assert_contains "$output" "-o StrictHostKeyChecking=no" "includes custom SSH option"
  assert_contains "$output" "SCP command: scp -O" "legacy scp adds -O"
}

test_quiet_option() {
  local output
  output="$(bash "$SCRIPT" my-vps --quiet --dry-run)"

  assert_contains "$output" "SCP command: scp -q" "--quiet enables quiet SCP mode"
}

test_json_dry_run() {
  local output
  output="$(bash "$SCRIPT" my-vps --size 1G --json --dry-run)"

  assert_contains "$output" '"target":"my-vps"' "JSON output includes target"
  assert_contains "$output" '"size":"1G"' "JSON output includes size"
  assert_contains "$output" '"test_file":"scp-speedtest-1G.bin"' "JSON dry-run output includes test file"
  assert_contains "$output" '"bytes":1073741824' "JSON output includes 1G byte count"
  assert_contains "$output" '"ssh_command":"ssh my-vps"' "JSON output includes SSH command"
  assert_not_contains "$output" "Target:" "JSON mode does not print human-readable labels"
}

test_connection_options() {
  local output
  output="$(bash "$SCRIPT" my-vps --connect-timeout 7 --max-duration 9 --dry-run)"

  assert_contains "$output" "-o ConnectTimeout=7" "connect timeout is passed to ssh/scp commands"
}

test_requires_bash() {
  assert_fails_contains "running with sh fails clearly" "requires bash" \
    sh "$SCRIPT" my-vps --dry-run
}

test_remote_scp_path_format() {
  # shellcheck disable=SC1090
  source "$SCRIPT"

  REMOTE_SPEC="nomi"
  LEGACY_SCP=0
  local default_path
  default_path="$(format_remote_scp_path "/tmp/scp-speedtest.abc/scp-speedtest-100M.bin")"
  [[ "$default_path" == "nomi:/tmp/scp-speedtest.abc/scp-speedtest-100M.bin" ]] ||
    fail "default SFTP scp path should not be shell-quoted. Actual: ${default_path}"
  pass "default SFTP scp path is not shell-quoted"

  LEGACY_SCP=1
  local legacy_path
  legacy_path="$(format_remote_scp_path "/tmp/scp-speedtest.abc/scp-speedtest-100M.bin")"
  [[ "$legacy_path" == "nomi:'/tmp/scp-speedtest.abc/scp-speedtest-100M.bin'" ]] ||
    fail "legacy scp path should be shell-quoted. Actual: ${legacy_path}"
  pass "legacy scp path keeps shell quoting"
}

test_partial_transfer_output() {
  # shellcheck disable=SC1090
  source "$SCRIPT"

  REMOTE_SPEC="partial-host"
  SIZE="100M"
  UPLOAD_STATUS="interrupted"
  UPLOAD_BYTES=11534336
  UPLOAD_SECONDS="21.000000"
  UPLOAD_MIBPS="0.52"
  DOWNLOAD_STATUS="completed"
  DOWNLOAD_BYTES=104857600
  DOWNLOAD_SECONDS="9.500000"
  DOWNLOAD_MIBPS="10.53"

  local output
  output="$(print_human_result 104857600)"

  assert_contains "$output" "Upload: interrupted, 11534336 / 104857600 bytes, 21.000000 seconds, 0.52 MiB/s" "interrupted upload prints transferred bytes"
  assert_contains "$output" "Download: completed, 104857600 / 104857600 bytes, 9.500000 seconds, 10.53 MiB/s" "interrupted upload does not affect full download output"
}

test_timeout_status_detection() {
  # shellcheck disable=SC1090
  source "$SCRIPT"

  is_timeout_status 124
  pass "timeout command exit status is treated as timeout"

  is_timeout_status 142
  pass "perl alarm exit status is treated as timeout"
}

make_fake_remote_fixture() {
  local fixture_dir="$1"
  local bin_dir="${fixture_dir}/bin"
  mkdir -p "$bin_dir" "${fixture_dir}/remote"

  cat >"${bin_dir}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

while (($#)); do
  case "$1" in
    -F|-p|-i|-J|-o)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done

remote="${1:-}"
script="${2:-}"
root="${FAKE_REMOTE_ROOT:?}"

map_path() {
  local path="$1"
  path="${path//\'/}"
  printf '%s%s' "$root" "$path"
}

if [[ "$script" == *"mktemp -d"* ]]; then
  mkdir -p "$root/tmp/scp-speedtest.fake"
  printf '/tmp/scp-speedtest.fake\n'
elif [[ "$script" == mkdir\ -p* ]]; then
  path="${script#*-- }"
  mkdir -p "$(map_path "$path")"
elif [[ "$script" == rm\ -f* ]]; then
  path="${script#*-- }"
  rm -f "$(map_path "$path")"
elif [[ "$script" == rm\ -rf* ]]; then
  path="${script#*-- }"
  rm -rf "$(map_path "$path")"
elif [[ "$script" == if\ \[\ -f*wc\ -c* ]]; then
  path="$(printf '%s' "$script" | sed -n "s/.*-f '\([^']*\)'.*/\1/p")"
  file="$(map_path "$path")"
  if [[ -f "$file" ]]; then
    wc -c <"$file" | tr -d '[:space:]'
    printf '\n'
  else
    printf '0\n'
  fi
elif [[ "$script" == if\ command\ -v\ truncate* ]]; then
  size="$(printf '%s' "$script" | sed -n 's/.*truncate -s \([0-9][0-9]*\).*/\1/p')"
  path="$(printf '%s' "$script" | sed -n "s/.*truncate -s [0-9][0-9]* '\([^']*\)'.*/\1/p")"
  file="$(map_path "$path")"
  mkdir -p "$(dirname "$file")"
  : >"$file"
  truncate -s "$size" "$file"
  printf 'truncate\n'
else
  printf 'fake ssh: unsupported command for %s: %s\n' "$remote" "$script" >&2
  exit 99
fi
EOF

  cat >"${bin_dir}/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=()
while (($#)); do
  case "$1" in
    -q|-O)
      shift
      ;;
    -F|-P|-i|-J|-o)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "${#args[@]}" -ne 2 ]]; then
  printf 'fake scp: expected source and destination, got %s args\n' "${#args[@]}" >&2
  exit 98
fi

root="${FAKE_REMOTE_ROOT:?}"
src="${args[0]}"
dst="${args[1]}"

map_remote() {
  local spec="$1"
  local path="${spec#*:}"
  path="${path//\'/}"
  printf '%s%s' "$root" "$path"
}

if [[ "$src" == *:* && "$dst" != *:* ]]; then
  src_file="$(map_remote "$src")"
  mkdir -p "$(dirname "$dst")"
  cp "$src_file" "$dst"
elif [[ "$src" != *:* && "$dst" == *:* ]]; then
  dst_file="$(map_remote "$dst")"
  mkdir -p "$(dirname "$dst_file")"
  cp "$src" "$dst_file"
else
  printf 'fake scp: unsupported direction: %s -> %s\n' "$src" "$dst" >&2
  exit 97
fi
EOF

  chmod +x "${bin_dir}/ssh" "${bin_dir}/scp"
}

test_fake_ssh_scp_full_flow_json() {
  local fixture_dir output
  fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/scp-speedtest-test.XXXXXX")"
  make_fake_remote_fixture "$fixture_dir"

  output="$(PATH="${fixture_dir}/bin:$PATH" FAKE_REMOTE_ROOT="${fixture_dir}/remote" bash "$SCRIPT" fake-host --size 1M --json --quiet)"

  assert_contains "$output" '"ok":true' "fake full flow JSON marks result ok"
  assert_contains "$output" '"test_file":"scp-speedtest-1M.bin"' "fake full flow JSON includes test file"
  assert_contains "$output" '"remote_generator":{"status":"completed","method":"truncate"}' "fake full flow records remote generator"
  assert_contains "$output" '"upload":{"status":"completed","bytes":1048576' "fake full flow records completed upload"
  assert_contains "$output" '"download":{"status":"completed","bytes":1048576' "fake full flow records completed download"

  rm -rf "$fixture_dir"
}

test_invalid_arguments() {
  assert_fails_contains "positional target and --target cannot be combined" "cannot be used together" \
    bash "$SCRIPT" my-vps --target other --dry-run

  assert_fails_contains "missing target fails" "provide alias-or-host" \
    bash "$SCRIPT" --dry-run

  assert_fails_contains "port must be numeric" "--port must be numeric" \
    bash "$SCRIPT" my-vps --port abc --dry-run

  assert_fails_contains "invalid size fails" "invalid --size value" \
    bash "$SCRIPT" my-vps --size 10Z --dry-run
}

test_no_arguments_prints_help
test_default_size_and_positional_target
test_target_option
test_size_specific_filename
test_explicit_connection_options
test_quiet_option
test_json_dry_run
test_connection_options
test_requires_bash
test_remote_scp_path_format
test_partial_transfer_output
test_timeout_status_detection
test_fake_ssh_scp_full_flow_json
test_invalid_arguments

printf 'All %d assertions passed.\n' "$PASS_COUNT"
