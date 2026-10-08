"""Optional cython-hidapi backend. Report ID is zero in uthiducs.dll BSS."""
import importlib
from .protocol import FRAME_SIZE, ProtocolError

VID = 0x0716
PID = 0x5060


def _hid():
    try:
        module = importlib.import_module("hid")
    except ImportError as exc:
        raise OSError("缺少 hidapi，请运行：.venv/bin/python -m pip install -r requirements.txt") from exc
    if not hasattr(module, "device") or not hasattr(module, "enumerate"):
        raise OSError("需要 cython-hidapi（pip 包名 hidapi），当前 hid 模块不兼容")
    return module


def enumerate_devices():
    return _hid().enumerate(VID, PID)


def device_summary(device):
    fields = ("vendor_id", "product_id", "release_number", "manufacturer_string",
              "product_string", "serial_number", "usage_page", "usage", "interface_number")
    result = {key: device.get(key) for key in fields}
    result["path_hex"] = device["path"].hex()
    return result


def select_device(devices, path_hex=None):
    if path_hex is not None:
        try:
            path = bytes.fromhex(path_hex)
        except ValueError as exc:
            raise OSError("--path-hex 不是有效十六进制路径") from exc
        devices = [d for d in devices if d["path"] == path]
    if not devices:
        raise OSError("未发现对应 HID 接口。按住 K2 的减号键，通过 CC1/HID 口连接 Mac 后再枚举")
    if len(devices) != 1:
        raise OSError("发现多个 HID 接口，请运行 devices 并用 --path-hex 指定唯一接口")
    selected = devices[0]
    if (selected.get("vendor_id"), selected.get("product_id")) != (VID, PID):
        raise OSError("所选接口 VID/PID 与 K2 配置不匹配")
    return selected


def normalize_input(raw):
    raw = bytes(raw)
    if len(raw) == FRAME_SIZE:
        return raw
    if len(raw) == FRAME_SIZE + 1 and raw[0] == 0:
        return raw[1:]
    if not raw:
        return b""
    raise ProtocolError(f"HID 输入长度 / Report ID 不匹配：{len(raw)} 字节")


class HidTransport:
    def __init__(self, selected):
        if (selected.get("vendor_id"), selected.get("product_id")) != (VID, PID):
            raise OSError("HID 接口 VID/PID 不匹配")
        self.device = _hid().device()
        try:
            self.device.open_path(selected["path"])
            self.device.set_nonblocking(0)
        except Exception:
            self.device.close()
            raise

    def write(self, frame):
        if len(frame) != FRAME_SIZE:
            raise ProtocolError("只能发送 64 字节协议帧")
        # HIDAPI's count includes its synthetic Report ID, including on macOS.
        count = self.device.write(b"\0" + frame)
        if count != FRAME_SIZE + 1:
            raise ProtocolError(f"HID 输出未完成：{count}/65 字节")
        return FRAME_SIZE

    def read(self, timeout_ms):
        # cython-hidapi treats timeout_ms=0 as hid_read(), which blocks unless
        # nonblocking is explicitly enabled. Positive values use read_timeout.
        if timeout_ms == 0:
            self.device.set_nonblocking(1)
            try:
                return normalize_input(self.device.read(FRAME_SIZE + 1))
            finally:
                self.device.set_nonblocking(0)
        return normalize_input(self.device.read(FRAME_SIZE + 1, timeout_ms))

    def close(self):
        self.device.close()
