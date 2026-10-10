# 静态分析脚本

本目录包含用于检查 WITRN UP V30 程序结构和 K2 固件容器的 Python 脚本。它们只对用户本地提供的文件执行分析；不会随仓库下载或运行厂商程序。

## 输入与输出

- `inspect_dotnet.py` 从项目根目录的 `WITRNUP.dll` 生成 `reverse/dotnet/` 中的方法和资源数据。
- `unpack_static.py`、`restore_methods.py`、`extract_delegates.py` 和 `parse_vm.py` 依赖这些中间产物；`restore_methods.py` 还会生成仅供分析的恢复 DLL。
- `extract_tables.py` 从根目录的 `WITRNUP.dll` 导出替换表和扇区表。
- `inspect_firmware.py` 读取 `reverse/tables/` 下的表和用户本地 `.k2` 样本。
- 生成物都位于被忽略的本地目录。运行前检查各脚本顶部的输入路径常量；不要提交厂商输入、反编译结果或中间文件。

## 典型执行顺序

在项目根目录安装脚本所需的分析依赖后，按以下顺序逐步执行；个别工具版本可能需要调整：

```sh
python3 -m pip install dnfile dncil pefile pycryptodome
python3 reverse/inspect_dotnet.py 440 665 1768
python3 reverse/unpack_static.py
python3 reverse/restore_methods.py
python3 reverse/extract_tables.py
cd reverse && python3 extract_delegates.py && python3 parse_vm.py
python3 reverse/inspect_firmware.py /path/to/K2_APP.k2 --output-dir /tmp/k2-firmware-analysis
```

ILSpy 用于独立反编译恢复后的托管程序集，不由这些脚本安装或调用。完整复现可能需要按源码调整路径、输入和工具版本；这些脚本是研究辅助工具，不是开箱即用的自动化构建流程。

分析结论和限制见 [`REPORT.md`](REPORT.md)，协议说明见 [`../docs/protocol.md`](../docs/protocol.md)。

## DFU 只读测速

`benchmark_dfu_reads.py` 比较现有批量读取、40/48/52 字节短读取，以及更大的批量请求。设备先进入 K2 DFU，并关闭其他占用 HID 的操作。在含 HIDAPI 的环境中运行：

```sh
.venv-app/bin/python reverse/benchmark_dfu_reads.py --sample-size 32768 --repeats 3
.venv-app/bin/python reverse/benchmark_dfu_reads.py --sample-size 65536 --repeats 3 --methods bulk
```

传输包装器仅放行命令 `3`、`10`、`11`，其余命令在送往设备前拒绝。先核对设备名称与已分析 Bootloader 的 SHA-256，再比较同一段应用数据；每帧检查校验和与长度，每轮逐字节比较批量读取基准，异常立即停止。没有并发请求或自动重试，不擦除、写入或退出 DFU。实验性大批量读取采用按长度扩展的超时，不改变正式升级器的 1024 字节限制。

结果 JSON 和原始帧日志默认写入被忽略的 `build/dfu-speed-research/`。模拟测试验证数据完整性与命令限制，不模拟真实设备的 USB 时序。实测结论见[协议文档](../docs/protocol.md#dfu-读取性能实测)。
