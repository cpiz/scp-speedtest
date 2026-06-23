# JSON Output Contract

`scp-speedtest --json` prints one JSON object to stdout. Progress events still go to stderr unless `--quiet` is used.

The JSON output has two shapes:

- Single-round output keeps the original flat shape for compatibility.
- Multi-round output uses a `rounds` array and a `summary` object.
- Runtime failure output uses `ok:false` and an `error` object.

The machine-readable schema is available at [`schemas/scp-speedtest-output.schema.json`](../schemas/scp-speedtest-output.schema.json).

## Single Round

```bash
./scp-speedtest.sh my-vps --json --quiet
```

```json
{
  "ok": true,
  "version": "1.1.3",
  "target": "my-vps",
  "size": "100M",
  "test_file": "scp-speedtest-100M.bin",
  "bytes": 104857600,
  "started_at": "2026-06-23T05:20:01Z",
  "ended_at": "2026-06-23T05:20:16Z",
  "remote_dir": "/tmp/scp-speedtest.xxxxxx",
  "remote_generator": {
    "status": "completed",
    "method": "truncate"
  },
  "upload": {
    "status": "completed",
    "bytes": 104857600,
    "seconds": 6.74674,
    "mib_per_second": 14.82
  },
  "download": {
    "status": "completed",
    "bytes": 104857600,
    "seconds": 7.041432,
    "mib_per_second": 14.2
  }
}
```

## Multiple Rounds

```bash
./scp-speedtest.sh my-vps --rounds 3 --json --quiet
```

Multi-round output includes:

- `round_count`: requested number of rounds.
- `rounds`: per-round transfer results.
- `summary`: average throughput across completed rounds only.

Interrupted or timed-out rounds remain visible in `rounds`, but they are not included in completed-round averages.

## Status Values

Transfer status values:

- `completed`
- `interrupted`
- `timeout`
- `skipped`

Remote generator status values:

- `completed`
- `skipped`

Remote generator method is usually `truncate` or `dd` when generation completed.

## Failure Output

When `--json` is enabled and a runtime command fails after argument validation, the script still exits non-zero and prints a structured JSON object to stdout:

```json
{
  "ok": false,
  "version": "1.1.3",
  "target": "my-vps",
  "size": "100M",
  "test_file": "scp-speedtest-100M.bin",
  "bytes": 104857600,
  "started_at": "2026-06-23T05:20:01Z",
  "ended_at": "2026-06-23T05:20:03Z",
  "error": {
    "step": "Connecting and creating remote temporary directory: my-vps",
    "exit_code": 255,
    "message": "runtime command failed; see stderr for ssh/scp details"
  }
}
```

The underlying `ssh` or `scp` error remains on stderr.
