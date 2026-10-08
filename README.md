# WITRN K2 Updater RE

对 WITRN K2 固件容器与 WITRN UP V30 Windows 升级流程的独立分析，以及一个实验性的 Python/HID 升级器实现。项目面向协议研究与设备维护；它不是 WITRN 官方软件，也不隶属于 WITRN。

> **风险提示：** `flash` 会擦除并写入 K2 应用区。设备型号、固件版本或传输条件不兼容时，设备可能无法启动。先阅读协议说明、检查固件并运行离线预演；只有在你能承担风险且已确认设备进入 DFU 时，才考虑实机操作。项目不保证适用于其他硬件、Bootloader 或固件版本。

## 项目范围

- 静态分析 K2 `.k2` 固件容器、HID 帧、命令及升级阶段。
- 提供离线 `inspect`、完整流程 `dry-run`、只读 `probe` / `backup` 和显式 `flash` 命令。
- 在写入后逐字节读回应用正文；只有校验一致才写提交标记并发送退出命令。
- 包含内存模拟传输和故障注入，用于检查主机端流程；模拟结果不证明真实硬件兼容。

分析依据与实现限制见[反向工程报告](reverse/REPORT.md)和[协议说明](docs/protocol.md)。项目曾在一台 K2 上完成一次 3.4 → 5.8 升级并校验完整读回；这不代表其他设备或版本已验证。没有随仓库发布设备备份、实机通信日志或厂商二进制。

## 安装

需要 Python 3.9 或更新版本。离线检查和模拟不需要 USB 权限或 HIDAPI；连接设备时安装 `requirements.txt` 中的 HIDAPI 后端：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

仓库不包含官方固件。请从 WITRN 官方渠道取得适用于你设备的 `.k2` 文件，并在本机指定文件路径。固件、厂商升级器和设备备份都被 `.gitignore` 排除；提交前仍应检查 `git status` 和待提交文件。

## 离线检查

```sh
python3 k2_updater.py inspect /path/to/K2_APP.k2
python3 k2_updater.py dry-run /path/to/K2_APP.k2
```

`inspect` 只检查本地文件。`dry-run` 使用内存模拟器跑完握手、擦除、写入、读回、提交和退出，不访问 USB。输出中的 `simulation_only: true` 与 `hardware_validated: false` 只描述模拟结果。

## 设备命令

先按设备和厂商说明进入 DFU，再连接支持数据传输的 USB 线。以下命令按只读探测、备份、显式刷写的顺序列出：

```sh
.venv/bin/python k2_updater.py devices
.venv/bin/python k2_updater.py probe --dfu
.venv/bin/python k2_updater.py backup --dfu --output-dir k2_backups/before-upgrade
```

备份会读取设备闪存并在本机生成镜像与恢复容器；它不是云端或仓库备份。请妥善保管，也不要公开上传。完成独立检查后，只有明确接受擦写风险才执行：

```sh
.venv/bin/python k2_updater.py flash /path/to/K2_APP.k2 --dfu --yes
```

`--yes` 是真实擦除/写入的显式确认。程序会在任何设备 I/O 前校验固件；识别不出 K2、回包校验失败、写入短缺或读回不一致时会停止。失败不会自动重试或发送收尾命令。若错误发生在擦除后，应用区可能处于不完整状态。

通信日志可能包含设备序列号、接口路径、设备信息和完整 HID 帧；日志默认保存在 `k2_logs/`。分享日志前请检查并脱敏。不要把真实日志、设备备份、序列号、个人路径或私有固件加入 Git。

## 开发

测试使用 Python 标准库和合成固件，不需要厂商程序、官方固件或连接设备：

```sh
python3 -m unittest discover -s tests -v
```

目录概览：

| 路径 | 内容 |
| --- | --- |
| `k2up/` | 固件解析、HID 协议、升级流程、备份、模拟器和 CLI |
| `reverse/` | 静态分析脚本与分析报告 |
| `docs/protocol.md` | 帧格式、命令、地址与执行顺序 |
| `tests/` | 合成样本上的离线回归测试 |

复现静态分析需要用户自行取得 WITRN UP V30 文件，并在本机运行 `reverse/` 下的脚本。原始厂商程序、反编译输出、IDA 数据库和固件均不由本仓库分发。详见 [`reverse/REPORT.md`](reverse/REPORT.md)。

## 许可与商标

本仓库原创代码和文档按 [MIT License](LICENSE) 授权；`k2up/data/firmware_decode.bin` 的说明见 [NOTICE](NOTICE.md)。WITRN、WITRN K2 及相关产品名称属于其各自权利人；本项目未获厂商认可或赞助。厂商程序、固件及其他第三方材料不包含在本仓库中，也不因本项目的许可声明而获得再许可。
