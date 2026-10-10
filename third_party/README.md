# 第三方来源

固件升级向导使用 [JohnScotttt/WITRN-K2-Quick-Reference-Manual](https://github.com/JohnScotttt/WITRN-K2-Quick-Reference-Manual) 第 7.1 节的 `pictures/DFU.png` 原图。下载日期：2026-10-10；图片未修改，通过白色背景呈现并支持放大。该仓库附有 GPL-3.0 许可证，全文保留在 `k2-quick-reference-GPL-3.0.txt`，随应用打包；界面提供原手册链接和来源说明。此图片不属于本项目 MIT 许可的原创内容。

`k2up/telemetry.py` 的遥测字段定义改编自 [didim99/witrn-driver](https://github.com/didim99/witrn-driver)，版本 `2729a02cde172631e36ad5be5a13a8bd1492ce0e`，Copyright (c) 2022 didim99，MIT 许可见同目录 LICENSE 文件。

修改：改为显式小端解析；增加输入长度、命令、有限数值校验；保留有符号和绝对功率；使用现有 HIDAPI，不复用上游 PyUSB 的重置和接口接管逻辑。记录、文件交换、统计及 SwiftUI 页面由本项目实现。
