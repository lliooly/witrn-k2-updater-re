# WITRN K2 Updater RE

对 WITRN K2 固件容器与 WITRN UP V30 Windows 升级流程的独立分析，以及 Python/HID 升级器与原生 macOS 维护工具。项目面向协议研究与设备维护；它不是 WITRN 官方软件，也不隶属于 WITRN。

> **风险提示：** `flash` 会擦除并写入 K2 应用区。设备型号、固件版本或传输条件不兼容时，设备可能无法启动。先阅读协议说明、检查固件并运行离线预演；只有在你能承担风险且已确认设备进入 DFU 时，才考虑实机操作。项目不保证适用于其他硬件、Bootloader 或固件版本。

## 项目范围

- 静态分析 K2 `.k2` 固件容器、HID 帧、命令及升级阶段。
- 提供离线 `inspect`、完整流程 `dry-run`、只读 `probe` / `backup` 和显式 `flash` 命令。
- 在写入后逐字节读回应用正文；只有校验一致才写提交标记并发送退出命令。
- 包含内存模拟传输和故障注入，用于检查主机端流程；模拟结果不证明真实硬件兼容。

分析依据与实现限制见[反向工程报告](reverse/REPORT.md)和[协议说明](docs/protocol.md)。项目曾在一台 K2 上完成一次 3.4 → 5.8 升级并校验完整读回；这不代表其他设备或版本已验证。没有随仓库发布设备备份、实机通信日志或厂商二进制。

## macOS 图形版

提供原生 SwiftUI 图形界面，默认进入上位机（曲线与记录），并提供固件升级、表盘、开机图和虚拟 E-Mark。设备连接统一放在可收起的右侧栏，切换页面不改变连接；工程文件操作、设备读写与任务状态分别组织。支持官方 `.pic` 导入导出、17 项布局元素的坐标／颜色／字号／精度编辑、画布拖动、BMP／PNG／JPEG 裁剪和缩放，以及包含图片的 `.k2project` 工程保存。各类资源分别读取、备份、写入和恢复；擦写前强制执行完整扇区双遍备份，读回校验覆盖整个擦除范围。窗口中不含模拟和测试入口。

K2Picture 格式与资源区依据见[静态分析记录](reverse/K2PICTURE.md)。0.3.0 的开机图写入已在本机 K2 上读回一致，用户确认重新上电正常显示；背景及布局资源的实机效果仍待验证。字体和基线预览为近似，屏幕使用固定示例值。

0.4.0 新增完整虚拟 E-Mark 管理：10 组配置、默认组及排序、官方 `.wtemark` 导入导出、名称和身份／线材参数、原始 VDO 编辑、`.k2emark` 工程与撤销。设备读取、写前双遍备份、完整扇区校验和恢复复用资源框架。格式及地址依据见 [E-Mark 静态分析](reverse/K2EMARK.md)；E-Mark 实机读写仍待验证。

0.5.0 新增「曲线与记录」：普通模式只读采集、电压／电流／功率／温度／D±曲线、长时间 SQLite 记录、暂停／继续、自动停止、历史文件与官方 CSV/SQLite 交换、区间统计和 PNG 曲线导出。采集协议改编自 MIT [witrn-driver](https://github.com/didim99/witrn-driver)，许可与修改见 [第三方说明](third_party/README.md)。0.5.1 修正 USB 到达时间抖动导致的采样漂移，并依据 K2 5.8 实机捕获启用遥测双校验。只读实机采集、暂停／继续、自动停止、无负载及正常充电负载读数对照、实机记录的三种格式往返已验证；反向接线及官方程序往返仍待验证。详见 [曲线工具说明](docs/k2-monitor.md)与[实机验证记录](docs/k2-monitor-hardware-validation.md)。

本地构建生成 `dist/K2 Updater.app`，内置 Python、HIDAPI 与 SQLite，面向 macOS 13+ 的 Apple Silicon / Intel；使用 ad-hoc 本地签名。本次交付旁路应用为 `dist/K2 Updater 0.5.1.app`。构建、使用方法和验证范围见 [macOS 图形版说明](docs/macos-app.md)。

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
| `macos/` | SwiftUI 应用、后台消息协议和 Swift 测试 |
| `script/` | 双架构后台构建、应用打包和签名检查 |

复现静态分析需要用户自行取得 WITRN UP V30 文件，并在本机运行 `reverse/` 下的脚本。原始厂商程序、反编译输出、IDA 数据库和固件均不由本仓库分发。详见 [`reverse/REPORT.md`](reverse/REPORT.md)。

## 许可与商标

本仓库原创代码和文档按 [MIT License](LICENSE) 授权；`k2up/data/firmware_decode.bin` 的说明见 [NOTICE](NOTICE.md)。WITRN、WITRN K2 及相关产品名称属于其各自权利人；本项目未获厂商认可或赞助。厂商程序、固件及其他第三方材料不包含在本仓库中，也不因本项目的许可声明而获得再许可。
