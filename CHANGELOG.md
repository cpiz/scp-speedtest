# 变更日志

本项目的所有重要变更都会记录在这里。

格式参考 Keep a Changelog；正式发布标签创建后，版本号遵循语义化版本。

## [1.1.1] - 2026-06-23

### 修复

- 默认增加 `LogLevel=ERROR`，压制跳板机链路中仍然出现的 OpenSSH warning 级别输出。

## [1.1.0] - 2026-06-23

### 变更

- 调整测速顺序为先下载、后上传。
- 人类可读结果和多轮汇总改为优先展示下载结果，再展示上传结果。

## [1.0.2] - 2026-06-23

### 新增

- 默认压制 OpenSSH `WarnWeakCrypto` 重复警告，避免测速输出被安全提示刷屏。
- 增加 `--show-ssh-warnings`，用于恢复显示 ssh/scp 原始安全警告。

## [1.0.1] - 2026-06-23

### 新增

- README 状态徽章。
- 可嵌入 README 的终端演示 SVG 和 asciinema cast 文件。

### 修复

- 修复通过 `curl ... | bash -s -- <target>` 从 stdin 执行时 `BASH_SOURCE[0]` 触发 unbound variable 的问题。

## [1.0.0] - 2026-06-23

### 新增

- 用于 `scp` 双向吞吐测速的 Bash CLI。
- SSH config alias 和显式 SSH 连接参数支持。
- 人类可读的关键事件输出和 JSON 输出。
- 支持上传/下载中断后的部分结果统计。
- 支持 `--rounds` 多轮测速和完成轮次平均值。
- 支持 `--remote-file-method auto|truncate|dd` 控制远端测试文件生成方式。
- 带项目地址、适合分享截图的结果卡片。
- 运行时失败时输出带项目地址的失败卡片。
- `--json` 运行时失败会输出结构化 `ok:false` 错误对象。
- 一行安装脚本和 `make dist` 打包目标。
- 使用 fake command fixture 的本地单元测试。
- Makefile 和 GitHub Actions CI。
- 默认英文 README 和中文 README。
- 贡献指南、安全策略、Issue/PR 模板和 JSON 输出契约。
