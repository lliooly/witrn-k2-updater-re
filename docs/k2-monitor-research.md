# K2 上位机调查

调查日期：2026-10-08。范围为 K2 实时曲线、长期记录、CSV/SQLite 交换和区间统计。当前阶段只审查源码和静态反编译，没有执行第三方程序或向设备发命令。

## 开源项目与选择

| 项目 | 已确认能力 | 局限及用途 |
| --- | --- | --- |
| [didim99/witrn-driver](https://github.com/didim99/witrn-driver) | MIT；README 列出社区测试过 K2；解析电压、电流、温度、D±、Ah/Wh 和运行时间 | PyUSB 传输会重置 USB 并接管接口；复用协议定义，传输改用本项目现有 HIDAPI |
| [Fescron/witrn-ui-bokeh](https://github.com/Fescron/witrn-ui-bokeh) | MIT；浏览器实时曲线、CSV 记录 | 作者仅测试 C4，历史文件回放列为 TODO；可参考交互，不作为原生界面的运行依赖 |
| [JohnScotttt/WITRN_HID_API](https://github.com/JohnScotttt/WITRN_HID_API) | HIDAPI；普通读数和 PD 报文解析 | 当前 LGPL-3.0-or-later、Python ≥3.10；现有后台为 Python 3.9，本次不复制其代码或引入依赖 |
| [JohnScotttt/witrn_pd_sniffer](https://github.com/JohnScotttt/witrn_pd_sniffer) | 独立 PD 报文工具 | 不是本次选择的完整曲线工具；不纳入此次实现 |
| [didim99/usbmeter-utils](https://github.com/didim99/usbmeter-utils) | 旧版记录文件转换 | 面向 U2p/旧版上位机，不能据此声称兼容当前官方 SQLite |

审查的源码版本：

- witrn-driver：`2729a02cde172631e36ad5be5a13a8bd1492ce0e`。
- witrn-ui-bokeh：`35493e5ae48989ca191932ae91b38865dcd94a39`。
- WITRN_HID_API：`f13f3374c91e76a26b557d3786832653b924e0f8`。

推荐：改编 MIT 驱动中的采集协议定义，保留许可证与来源说明，结合现有 HIDAPI、Python SQLite 和 SwiftUI。没有找到能直接替换现有应用、同时满足所选全部功能的 Mac 项目。

## 官方程序证据

[官方使用说明](https://www.witrn.com/?p=873)介绍实时读数、曲线、历史文件、长时间记录和区间统计。本地输入 `WITRN_PC_V1.0.4/WITRN.exe` 是原生 x86_64 Qt 程序，SHA-256：`1260bf387882900d97a47f06c929222eb8f67db4cdb2b4cc46c2fec4a21c8e6e`。

IDA 静态分析定位到以下函数；自动推断的 Qt 函数参数不可靠，地址和字符串引用用于复核：

- `0x140014F60`：循环 `hid_read_timeout`，读取普通数据，没有遥测启动写命令。
- `0x140014DA0`：遥测解析，检查至少 64 字节、报告偏移 8 的命令 `0x1A`；功率由电压乘以电流绝对值计算。
- `0x1400BA290`：CSV 导出，包含 BOM、元信息行、可选列及 Excel 风格时间字符串。
- `0x1400B3BE0`：SQLite 导出，两张表与 CSV 同名字段。
- `0x1400E0810`：时间文本格式，24 小时内 `hh:mm:ss.mmm`，超过一天加 `D.` 前缀。

普通报告为 64 字节。以下偏移从报告第一个字节开始，浮点与整数按小端解析；与 MIT 驱动定义及官方解析交叉核对：

| 偏移 | 类型 | 含义 |
| --- | --- | --- |
| 8 | uint8 | 命令 `0x1A` |
| 9 | uint8 | 有效载荷长度 |
| 14、18 | float32 | 设备累计 Ah、Wh |
| 22、26 | uint32 | 设备记录秒数、开机秒数 |
| 30、34 | float32 | D+、D− 电压 |
| 38、42 | float32 | 内部、外部温度 |
| 46、50 | float32 | 电压、有符号电流 |
| 54 | uint8 | 从 0 开始的设备记录组 |

官方曲线程序显示外部温度，将非正值显示为零；我们的内部/外部温度各自标注，不把缺失值当作有效测量。官方程序和上述 MIT 驱动都没有严格检查遥测校验字节；不能仅因 DFU 帧采用双校验，就推断全部遥测具有相同校验行为。实现前以只读实机捕获核对头部、长度和校验规则；没有设备时保留验证边界。

### 官方交换格式

CSV 元信息键为 `SUM`、`TotalTime`、`SampTime(ms)`、`DateTime`，之后空行和列标题。必选列：`Time(D.hh:mm:ss.ms)`、`Voltage(V)`、`Current(A)`、`Power(W)`；可选列：`Temp(°C)`、`D+(V)`、`D-(V)`。时间可能为 `="00:00:01.234"`，行尾可能有逗号。

SQLite `metadata(key TEXT PRIMARY KEY, value TEXT)` 保存上述元信息；`records` 有自增 `id`，其余列与 CSV 标题同名，官方以 TEXT 保存数值。缺失可选列是合法情况。兼容导出保留官方非负功率约定，本地记录另外保存有符号功率及分段信息。

这些结论来自静态证据；尚未取得官方实际导出样本，未做 Windows 官方程序往返测试。不能将合成样本往返当作官方兼容实测。

## 当前验证边界

初次调查时没有连接 K2。2026-10-08 已对普通模式 K2 5.8 进行只读捕获：连续 12 秒的 1201 个报告均为 `FF 55` 头、`0x1A` 命令、52 字节载荷，且偏移 62 为 `sum(report[8:62]) & 0xff`，偏移 63 为 `sum(report[:62]) & 0xff`。后续采集也未发现校验不匹配，0.5.1 因而启用双校验并拒绝坏帧；尚未验证其他固件或硬件版本。实机记录和采样修正结果见[实机验证记录](k2-monitor-hardware-validation.md)。

CC1/CC2、远程采样率设置、设备离线存储下载均未独立确认，不作为首版功能承诺。普通采集保持只读，不调用 DFU 握手、擦写或 USB reset。

官方程序、第三方完整源码和 IDA 数据库留在被忽略目录。仓库只提交原创说明和必要的 MIT 改编代码及许可。
