"""K2Picture resource formats and fixed flash allocations, no USB access."""
from dataclasses import dataclass
import hashlib
import struct

MAGIC = b"\x5a\xa5\x5a\xa5"
SECTOR_SIZE = 2048
FONT_HEIGHTS = (11, 16, 21, 27, 40, 46, 58)
PRECISION_FIELDS = {0: (0, 2, 7), 1: (1, 2, 7), 2: (2, 3, 7),
                    4: (3, 2, 3), 5: (4, 2, 3), 9: (5, 2, 3),
                    10: (6, 2, 3), 15: (7, 3, 7)}


@dataclass(frozen=True)
class Resource:
    kind: str
    address: int
    size: int
    sectors: int
    dimension: int = 0

    @property
    def allocation(self):
        return self.sectors * SECTOR_SIZE

    @property
    def addresses(self):
        return range(self.address, self.address + self.allocation, SECTOR_SIZE)

    def validate(self, data):
        if len(data) != self.size:
            raise ValueError(f"{self.kind} 数据长度错误：{len(data)}，预期 {self.size}")
        if data[:4] != MAGIC or data[-4:] != MAGIC:
            raise ValueError("资源头尾标记错误")
        if self.kind == "layout":
            for index in range(17):
                _, _, _, enabled, font = struct.unpack_from("<IhhBB", data, 4 + index * 10)
                if enabled not in (0, 1):
                    raise ValueError(f"表盘元素 {index + 1} 的显示开关无效")
                if index not in (13, 14) and enabled and font >= len(FONT_HEIGHTS):
                    raise ValueError(f"表盘元素 {index + 1} 的字号无效")
                if enabled and index in PRECISION_FIELDS:
                    position, low, high = PRECISION_FIELDS[index]
                    if not low <= data[224 + position] <= high:
                        raise ValueError(f"表盘元素 {index + 1} 的小数位应为 {low}…{high}")
            if any(value > 9 for value in data[224:232]):
                raise ValueError("数字精度超出支持范围")
        return bytes(data)


RESOURCES = {
    "background": Resource("background", 0x080C6800, 115208, 57, 240),
    "layout": Resource("layout", 0x080E4000, 400, 1),
    "startup": Resource("startup", 0x080E4800, 110458, 54, 235),
}


def resource_for(kind):
    try:
        return RESOURCES[kind]
    except (KeyError, TypeError):
        raise ValueError("资源类型必须是 layout、background 或 startup") from None


def sha(data):
    return hashlib.sha256(data).hexdigest()
