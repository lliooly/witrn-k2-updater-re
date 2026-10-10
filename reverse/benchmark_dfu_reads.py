"""Read-only comparison of K2 bulk reads and the bootloader's short-read path.

The transport permits only handshake (3), short read (10), and bulk read (11).
Experiments are restricted to the bootloader fingerprint analyzed locally.
Results and raw captures stay under ignored build/ by default.
"""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import statistics
import struct
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from k2up.cli import Trace, TracedTransport
from k2up.firmware import APP_START
from k2up.protocol import Protocol, ProtocolError, parse_frame
from k2up.transport import HidTransport, enumerate_devices, select_device
from k2up.updater import Updater

BOOTLOADER_SHA256 = "406e15789802ff58f534b0d9550b041580104168d6c543d6fb02b198449424e7"


class ReadOnlyTransport:
    def __init__(self, transport):
        self.transport = transport
        self.commands = Counter()

    def write(self, frame):
        command = parse_frame(frame).command
        if command not in (3, 10, 11):
            raise ProtocolError(f"Read-only benchmark refuses command {command}")
        self.commands[command] += 1
        return self.transport.write(frame)

    def read(self, timeout_ms):
        return self.transport.read(timeout_ms)

    def close(self):
        self.transport.close()


def read_short(protocol, address, size):
    if not 1 <= size <= 52:
        raise ValueError("Short reads must fit one 52-byte payload")
    protocol.drain()
    protocol._send(10, struct.pack("<IB", address, size))
    data = protocol._receive(10, time.monotonic() + protocol.timeout_ms / 1000)
    if len(data) != size:
        raise ProtocolError(f"Short read returned {len(data)} bytes, expected {size}")
    return data


def read_bulk(protocol, address, size):
    """Experimental U16 request, still receiving and checking every 40-byte frame."""
    if not 1 <= size <= 65520:
        raise ValueError("Bulk experiment length must be 1–65520 bytes")
    protocol.drain()
    protocol._send(11, struct.pack("<IH", address, size))
    deadline = time.monotonic() + max(protocol.timeout_ms / 1000, size / 10000 + 1)
    data = bytearray()
    while len(data) < size:
        chunk = protocol._receive(11, deadline)
        expected = min(40, size - len(data))
        if len(chunk) != expected:
            raise ProtocolError(f"Bulk read returned {len(chunk)} bytes, expected {expected}")
        data.extend(chunk)
    return bytes(data)


def read_region(protocol, address, size, block, short=False):
    data = bytearray()
    for offset in range(0, size, block):
        length = min(block, size - offset)
        data.extend((read_short if short else read_bulk)(protocol, address + offset, length))
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-size", type=int, default=32768)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--methods", choices=("short", "bulk"), default="short")
    parser.add_argument("--output-dir", type=Path, default=Path("build/dfu-speed-research"))
    args = parser.parse_args()
    if not 1024 <= args.sample_size <= 65536 or not 1 <= args.repeats <= 5:
        parser.error("Sample size must be 1024–65536 bytes; repeats must be 1–5")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    trace = Trace(args.output_dir / f"read-benchmark-{stamp}.jsonl")
    transport = None
    results = []
    try:
        selected = select_device(enumerate_devices())
        transport = ReadOnlyTransport(HidTransport(selected))
        protocol = Protocol(TracedTransport(transport, trace))
        identity = Updater(protocol).probe()
        if not identity.confirmed_k2:
            raise ProtocolError("Device is not confirmed as a K2 in DFU")
        boot = read_region(protocol, 0x08000000, 14336, 1024)
        if hashlib.sha256(boot).hexdigest() != BOOTLOADER_SHA256:
            raise ProtocolError("Bootloader differs from the analyzed short-read implementation")
        print(f"K2 DFU verified; firmware {identity.current_version}; bootloader fingerprint matches", flush=True)
        baseline = read_region(protocol, APP_START, args.sample_size, 1024)
        for repeat in range(args.repeats):
            # Rotate the order to reduce systematic warm-up/order effects.
            methods = [("bulk-1024", 1024, False), ("short-40", 40, True),
                       ("short-48", 48, True), ("short-52", 52, True)]
            if args.methods == "bulk":
                methods = [(f"bulk-{block}", block, False) for block in (1024, 1000, 4000, 16000)]
            methods = methods[repeat:] + methods[:repeat]
            for name, block, short in methods:
                trace.event("benchmark-start", method=name, repeat=repeat)
                start = time.perf_counter()
                data = read_region(protocol, APP_START, args.sample_size, block, short)
                seconds = time.perf_counter() - start
                if data != baseline:
                    raise ProtocolError(f"{name} differs from bulk reference; experiment stopped")
                row = {"method": name, "repeat": repeat, "bytes": len(data), "seconds": seconds,
                       "bytes_per_second": len(data) / seconds, "matches_bulk": True}
                results.append(row)
                trace.event("benchmark-result", **row)
                print(f"{name}: {seconds:.3f}s, {len(data)/seconds/1024:.1f} KiB/s; bytes match", flush=True)
        medians = {name: statistics.median(row["seconds"] for row in results if row["method"] == name)
                   for name in sorted({row["method"] for row in results})}
        report = {"read_only": True, "bootloader_sha256": BOOTLOADER_SHA256,
                  "identity": identity.summary(), "method_group": args.methods,
                  "sample_size": args.sample_size, "results": results, "median_seconds": medians,
                  "commands_sent": dict(transport.commands)}
        target = args.output_dir / f"read-benchmark-{stamp}.json"
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"Report: {target}", flush=True)
    except Exception as exc:
        trace.event("error", message=str(exc))
        raise
    finally:
        if transport is not None:
            transport.close()
        trace.close()


if __name__ == "__main__":
    main()
