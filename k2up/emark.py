"""Independent WITRN .wtemark / K2 bank validation, no USB access."""
import struct

RECORD_SIZE = 66
BANK_SIZE = 666
CAPACITY = 10


def validate_record(data):
    if len(data) != RECORD_SIZE:
        raise ValueError(".wtemark 长度必须是 66 字节")
    if data[65] != (sum(data[:65]) + 0xA5) & 255:
        raise ValueError("E-Mark 配置校验失败")
    if 0 not in data[:19]:
        raise ValueError("E-Mark 名称缺少结束符")
    if data[20] not in (1, 2):
        raise ValueError("E-Mark PD 版本编码必须是 1（2.0）或 2（3.x）")
    return bytes(data)


def validate_bank(data):
    if len(data) != BANK_SIZE:
        raise ValueError("E-Mark 配置集合长度必须是 666 字节")
    selected, count = data[4:6]
    if count > CAPACITY or (selected >= count if count else selected != 0):
        raise ValueError("E-Mark 配置数量或默认组无效")
    for index in range(count):
        validate_record(data[6 + index * RECORD_SIZE:6 + (index + 1) * RECORD_SIZE])
    # Inactive slots and the four-byte header are preserved, not regenerated.
    return bytes(data)


def sample_record(name="K2 configuration"):
    """Synthetic development fixture; not a manufacturer cable profile."""
    data = bytearray(RECORD_SIZE)
    label = name.encode("ascii")
    if len(label) > 18:
        raise ValueError("名称过长")
    data[:len(label)] = label
    data[20] = 2
    struct.pack_into("<I", data, 25, (3 << 27) | (2 << 21))
    struct.pack_into("<I", data, 37, (2 << 5) | (3 << 9) | (1 << 17) | (3 << 21))
    data[-1] = (sum(data[:-1]) + 0xA5) & 255
    return validate_record(data)


def sample_bank():
    data = bytearray(b"\xff" * BANK_SIZE)
    data[4:6] = bytes((0, 1))
    data[6:72] = sample_record()
    return validate_bank(data)
