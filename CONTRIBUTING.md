# Contributing

Thanks for considering a contribution to `scp-speedtest`.

This project is intentionally small: one Bash CLI, lightweight tests, and no runtime dependencies beyond standard Unix tools plus `ssh/scp`.

## Development Setup

```bash
git clone https://github.com/cpiz/scp-speedtest.git
cd scp-speedtest
make check
```

Optional tools:

- `shellcheck` for Bash linting.
- `shfmt` for Bash formatting.

## Checks

Run these before opening a pull request:

```bash
make lint
make format-check
make check
```

`make check` runs syntax checks and the local fake `ssh/scp` test suite. The test suite does not require access to a real SSH host.

## Style

- Keep the CLI implementation in Bash.
- Keep shell output, comments, and user-facing CLI text in English.
- Prefer portable macOS/Linux behavior.
- Avoid adding runtime dependencies unless they solve a real portability or correctness problem.
- Keep the default behavior backward-compatible where practical.
- Document new command-line options in `README.md`, `README.zh-CN.md`, and `CHANGELOG.md`.

## Commits

Use English Conventional Commits:

```text
feat: add multi-round speed tests
fix: handle interrupted download cleanup
docs: update json output contract
test: cover legacy scp paths
```

## Pull Requests

Good pull requests include:

- A short description of the user-facing change.
- The commands used to verify the change.
- Notes about compatibility, especially for macOS, Linux, OpenSSH, or legacy scp behavior.

For behavior changes, please add or update tests in `tests/run_tests.sh`.
