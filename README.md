# scp-speedtest

[中文文档](README.zh-CN.md)

A Bash CLI that measures bidirectional network throughput with `scp`. It creates fixed-size test files on both the local and remote sides: the local file is used for upload testing, and the remote file is used for download testing, so the two directions are measured independently.

The default test file size is `100M`. Authentication, keys, jump hosts, SSH config, and prompts are handled by the system `ssh/scp` commands.

## Quick Start

Run the script without arguments to print usage, options, and examples:

```bash
./scp-speedtest.sh
```

```bash
chmod +x scp-speedtest.sh
./scp-speedtest.sh my-vps
```

`my-vps` can be a `Host` alias from `~/.ssh/config` or a regular hostname.

Run directly from GitHub for a one-off test:

```bash
curl -fsSL https://raw.githubusercontent.com/cpiz/scp-speedtest/v1.0.0/scp-speedtest.sh | bash -s -- my-vps
```

For regular use, download the script first and review it before running.
Use `main` instead of a version tag only when you intentionally want the latest development version.

Equivalent explicit target syntax:

```bash
./scp-speedtest.sh --target my-vps
```

Specify connection settings directly:

```bash
./scp-speedtest.sh --host 1.2.3.4 --user root --port 2222 --identity-file ~/.ssh/id_ed25519
```

Use a larger test file and print JSON:

```bash
./scp-speedtest.sh my-vps --size 1G --json
```

Run multiple rounds and print averages:

```bash
./scp-speedtest.sh my-vps --rounds 3
```

## Installation

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/cpiz/scp-speedtest/v1.0.0/install.sh | bash
```

Install to a user-writable prefix:

```bash
curl -fsSL https://raw.githubusercontent.com/cpiz/scp-speedtest/v1.0.0/install.sh | PREFIX="$HOME/.local" bash
```

Install to `/usr/local/bin/scp-speedtest`:

```bash
sudo make install
```

Install to a custom prefix:

```bash
make install PREFIX="$HOME/.local"
```

Uninstall:

```bash
sudo make uninstall
```

Build a release-style tarball:

```bash
make dist
```

## Options

```text
./scp-speedtest.sh [alias-or-host] [options]

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
--dry-run                      Show resolved commands without running the test
-h, --help                     Show help
--version                      Show version
```

## Output Examples

Human-readable output:

```text
[13:20:01] Target: my-vps
[13:20:01] Creating local test file: /tmp/scp-speedtest.local.xxxxxx/scp-speedtest-100M.bin (100M / 104857600 bytes)
[13:20:01] Local test file created; calculating source checksum
[13:20:02] Connecting and creating remote temporary directory: my-vps
[13:20:02] Remote temporary directory created: /tmp/scp-speedtest.xxxxxx
[13:20:02] Starting upload: /tmp/scp-speedtest.local.xxxxxx/scp-speedtest-100M.bin -> my-vps:/tmp/scp-speedtest.xxxxxx/scp-speedtest-100M.bin
scp-speedtest-100M.bin                     100%  100MB  14.8MB/s   00:06
[13:20:09] Upload completed: 104857600 bytes, 6.746740 seconds, 14.82 MiB/s
[13:20:09] Preparing remote download test file: my-vps:/tmp/scp-speedtest.xxxxxx/scp-speedtest-100M.bin (100M / 104857600 bytes)
[13:20:09] Remote download test file ready
[13:20:09] Starting download: my-vps:/tmp/scp-speedtest.xxxxxx/scp-speedtest-100M.bin -> /tmp/scp-speedtest.local.xxxxxx/download/scp-speedtest-100M.bin
scp-speedtest-100M.bin                     100%  100MB  14.2MB/s   00:07
[13:20:16] Download completed: 104857600 bytes, 7.041432 seconds, 14.20 MiB/s
[13:20:16] Verifying downloaded file checksum
[13:20:16] Checksum verification passed
======================================================================
scp-speedtest result
GitHub   : https://github.com/cpiz/scp-speedtest
Target   : my-vps
Test file: scp-speedtest-100M.bin (100.00 MiB / 104857600 bytes)
----------------------------------------------------------------------
Upload   : COMPLETED       100.00 / 100.00    MiB    6.746740 s     14.82 MiB/s
Download : COMPLETED       100.00 / 100.00    MiB    7.041432 s     14.20 MiB/s
======================================================================
```

JSON output:

```json
{"ok":true,"version":"1.0.0","target":"my-vps","size":"100M","test_file":"scp-speedtest-100M.bin","bytes":104857600,"started_at":"2026-06-23T05:20:01Z","ended_at":"2026-06-23T05:20:16Z","remote_dir":"/tmp/scp-speedtest.xxxxxx","remote_generator":{"status":"completed","method":"truncate"},"upload":{"status":"completed","bytes":104857600,"seconds":6.746740,"mib_per_second":14.82},"download":{"status":"completed","bytes":104857600,"seconds":7.041432,"mib_per_second":14.20}}
```

See [JSON Output Contract](docs/json-output.md) for the stable field contract and schema.

## How It Works

1. Create an upload test file in a local temporary directory.
2. Create a remote temporary directory with `ssh`, or use the directory passed with `--remote-dir`.
3. Create a same-size download test file on the remote host.
4. Upload the local test file with `scp` and measure elapsed time.
5. Download the remote test file with `scp` and measure elapsed time.
6. Verify the completed download with a SHA-256 checksum.
7. Clean up local and remote temporary files by default.

Checksum verification is not included in upload or download timing.

Progress events and the native `scp` progress output are written to stderr. Final results and JSON output are written to stdout. Use `--quiet` for quiet mode.

## Interrupt Handling

Pressing `Ctrl-C` during a transfer interrupts the current `scp` stage, but the script continues with the next stage and prints the data collected so far:

- Interrupted upload: the script records the remote uploaded file size, then continues to download the independently generated full remote test file.
- Interrupted download: the script records the local downloaded file size, then proceeds to cleanup and result output.
- Checksum verification is skipped when the download is incomplete. If only the upload was interrupted and the download completes, the download is still verified.
- Cleanup still attempts to remove the local temporary directory, remote test file, and remote temporary directory.

Partial transfer example:

```text
Upload: interrupted, 11534336 / 104857600 bytes, 21.000000 seconds, 0.52 MiB/s
Download: completed, 104857600 / 104857600 bytes, 9.500000 seconds, 10.53 MiB/s
```

## Multiple Rounds

Use `--rounds <count>` to run the same test multiple times:

```bash
./scp-speedtest.sh my-vps --rounds 3
```

Each round creates fresh local and remote temporary files and cleans them up before the next round. Human-readable output prints each round and a final summary. The summary average uses completed rounds only, so interrupted or timed-out rounds remain visible but do not distort the completed-round average.

For JSON output, single-round output keeps the original flat shape for compatibility. Multi-round JSON uses a `rounds` array plus a `summary` object.

## Remote File Generation

Download tests require a same-size file on the remote host. By default, `--remote-file-method auto` uses `truncate` when available and falls back to `dd`.

Use `--remote-file-method dd` when you want the remote file to be fully written with zero bytes instead of being sparse. This can better represent remote disk reads, but it increases preparation time before the download test starts.

Use `--remote-file-method truncate` when you explicitly want fast sparse-file generation and prefer the command to fail if `truncate` is unavailable.

## Interpreting Results

- Upload and download can differ substantially because routes, cloud egress policy, CPU, ciphers, and storage paths are not symmetric.
- `scp-speedtest` measures real `scp` application-level throughput. It includes SSH encryption and `scp` protocol overhead, so it will usually differ from `iperf3`.
- Interrupted or timed-out transfers are still useful for spotting obviously slow links. They show transferred bytes, elapsed seconds, and observed throughput up to the interruption.
- Multi-round averages include completed rounds only. Interrupted rounds stay visible in per-round output.
- If a download looks much slower than upload, try `--remote-file-method dd` to avoid sparse remote files and compare again.

## Accuracy Notes

This tool measures actual `scp` application-level throughput, not raw TCP bandwidth. Results can be affected by:

- SSH ciphers and local/remote CPU.
- Whether `scp` uses SFTP mode or legacy scp mode.
- Local and remote disk or filesystem performance.
- Cloud provider throttling, QoS, and route instability.
- SSH config options such as ProxyJump, ProxyCommand, IPQoS, and Compression.

If you need raw network capacity, `iperf3` is a better fit. If you care about real-world `scp` file transfer behavior, this tool is closer to that workload.

## Notes

- This tool measures `scp` transfer throughput, not raw network bandwidth.
- Passwords are not accepted or stored by the script. Use SSH agent, keys, SSH config, or the native `ssh/scp` prompt.
- Use `--legacy-scp` for servers that require the old scp protocol.
- Use `--dry-run` to inspect command construction without connecting to the remote host.
- Use `--quiet` to hide progress events and the `scp` progress bar.
- Use `--max-duration <seconds>` when a link is slow and you want a transfer timeout instead of a manual interrupt.
- Use `--remote-file-method dd` when remote sparse files may make download results less representative.
- Runtime failures print a final failure card with the target, failed step, exit code, and project URL.

## Local Verification

```bash
make test
make lint
make format-check
```

Equivalent manual commands:

```bash
bash -n scp-speedtest.sh
bash -n tests/run_tests.sh
tests/run_tests.sh
```

If `shellcheck` is installed:

```bash
shellcheck scp-speedtest.sh tests/run_tests.sh
```

## Development And Release

- CI runs on Ubuntu and macOS.
- Update `CHANGELOG.md` before release.
- The version is maintained in `VERSION` near the top of `scp-speedtest.sh`.
- The project is MIT licensed. See `LICENSE`.

## Project Links

- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [JSON output contract](docs/json-output.md)
