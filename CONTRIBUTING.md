# 参与贡献

欢迎提交能让协议说明、离线检查或错误处理更清楚的改进。请先确认改动不依赖仓库中没有分发的厂商文件或个人设备数据。

## 提交前

- 代码保持兼容项目声明的 Python 版本，避免增加不必要的运行依赖。
- 修改固件解析或 HID 时序时，说明依据、适用范围和失败处理。
- 对协议改动补充合成样本或模拟器覆盖；不要把真实设备捕获直接提交。
- 运行 `python3 -m unittest discover -s tests -v`，并在 PR 中说明结果。
- 检查 `git status` 和 PR diff；不要上传固件、厂商二进制、备份、通信日志、序列号、密钥或个人路径。

## Commit 与 PR

Commit message 建议使用 Conventional Commits，例如 `fix(protocol): reject malformed read response` 或 `docs: clarify recovery limitations`。PR 应描述目的、改动范围、验证方式及可能影响刷写安全性的行为变化。

涉及真实硬件时，说明设备型号和固件/Bootloader 范围即可。除非必要，不要公开设备标识、原始日志或镜像。
