"""Streaming official WITRN CSV/SQLite exchange and local SQLite backup."""
import csv
from dataclasses import replace
import math
from pathlib import Path
import re
import sqlite3
from statistics import median
import tempfile
import os

from .recording import Recording, metadata, readonly, samples, validate_local
from .telemetry import Sample

TIME = "Time(D.hh:mm:ss.ms)"
OFFICIAL = (TIME, "Voltage(V)", "Current(A)", "Power(W)", "Temp(°C)", "D+(V)", "D-(V)")
KEYS = ("SUM", "TotalTime", "SampTime(ms)", "DateTime")


def elapsed_text(value):
    total = round(value * 1000)
    days, remainder = divmod(total, 86400000)
    hours, remainder = divmod(remainder, 3600000)
    minutes, remainder = divmod(remainder, 60000)
    seconds, ms = divmod(remainder, 1000)
    return (str(days) + "." if days else "") + f"{hours:02}:{minutes:02}:{seconds:02}.{ms:03}"


def parse_time(text):
    text = str(text).strip()
    if text.startswith('="') and text.endswith('"'): text = text[2:-1]
    match = re.fullmatch(r"(?:(\d+)\.)?(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,3})", text)
    if not match: raise ValueError("时间应为 [D.]hh:mm:ss.mmm")
    days, hours, minutes, seconds, ms = match.groups()
    if int(hours) > 23 or int(minutes) > 59 or int(seconds) > 59:
        raise ValueError("时间字段超出范围")
    return (int(days or 0) * 86400 + int(hours) * 3600 + int(minutes) * 60 + int(seconds) + int(ms.ljust(3, "0")) / 1000)


def number(text, optional=False):
    if text is None or str(text).strip() == "":
        if optional: return None
        raise ValueError("缺少数值")
    value = float(text)
    if not math.isfinite(value): raise ValueError("非有限数值")
    return value


def row_sample(row):
    t = parse_time(row[TIME])
    v, i = number(row["Voltage(V)"]), number(row["Current(A)"])
    p = number(row.get("Power(W)"), True)
    if v < 0: raise ValueError("电压不能为负")
    return Sample(t, v, i, p if p is not None else v * abs(i), v * i,
                  temp_out=number(row.get("Temp(°C)"), True),
                  dp=number(row.get("D+(V)"), True), dn=number(row.get("D-(V)"), True))


def csv_source(path, meta):
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        reader = csv.reader(source)
        header = None
        for row in reader:
            while row and not row[-1].strip(): row.pop()
            if not row: continue
            if header is None:
                if row[0] in KEYS:
                    meta[row[0]] = row[1] if len(row) > 1 else ""
                    continue
                header = [r.strip() for r in row]
                if not {TIME, "Voltage(V)", "Current(A)"}.issubset(header) or len(header) != len(set(header)):
                    raise ValueError(f"CSV 第 {reader.line_num} 行：列标题无效")
                continue
            # Optional empty last value is meaningful after a known header.
            if len(row) > len(header):
                raise ValueError(f"CSV 第 {reader.line_num} 行：列数过多")
            row += [""] * (len(header) - len(row))
            try: yield row_sample(dict(zip(header, row)))
            except (ValueError, KeyError) as exc: raise ValueError(f"CSV 第 {reader.line_num} 行：{exc}") from exc
        if header is None: raise ValueError("CSV 缺少标题")


def sqlite_source(path, meta):
    db = readonly(path)
    try:
        meta.update(metadata(db))
        if "k2_schema" in meta:
            validate_local(db)
            previous = None
            for sample in samples(db):
                vals = sample.dictionary()
                if any(not math.isfinite(v) for v in vals.values() if v is not None):
                    raise ValueError("本地记录含非法数值")
                if sample.time < 0 or sample.voltage < 0 or (previous is not None and sample.time < previous):
                    raise ValueError("本地记录时间或电压无效")
                previous = sample.time
                yield sample
        else:
            cols = {r[1] for r in db.execute("PRAGMA table_info(records)")}
            if not {"id", TIME, "Voltage(V)", "Current(A)"}.issubset(cols):
                raise ValueError("官方 SQLite 缺少 records 必要列")
            supported = [c for c in OFFICIAL if c in cols]
            sql = "SELECT " + ",".join('"' + c + '"' for c in supported) + " FROM records ORDER BY id"
            for index, row in enumerate(db.execute(sql), 1):
                try: yield row_sample(dict(row))
                except ValueError as exc: raise ValueError(f"SQLite 第 {index} 条：{exc}") from exc
    finally:
        db.close()


def import_record(source, destination, cancelled=lambda: False):
    meta = {}
    source = Path(source).resolve(strict=True)
    destination = Path(destination).resolve()
    if source == destination: raise ValueError("导入目标不能覆盖原文件")
    with source.open("rb") as stream: magic = stream.read(16)
    iterator = sqlite_source(source, meta) if magic == b"SQLite format 3\0" else csv_source(source, meta)
    recording = None
    # Read a bounded prefix to infer rate without loading the recording.
    prefix = []
    try:
        for _ in range(1001):
            if cancelled(): raise InterruptedError("导入已取消")
            item = next(iterator, None)
            if item is None: break
            prefix.append(item)
        gaps = [b.time - a.time for a, b in zip(prefix, prefix[1:]) if b.time > a.time]
        configured = number(meta.get("SampTime(ms)"), True)
        interval = configured / 1000 if configured and configured > 0 else (median(gaps) if gaps else 1)
        local = "k2_schema" in meta
        rate = meta.get("rate", 0)
        recording = Recording(destination, rate, {"DateTime": meta.get("DateTime", ""), "source_format": "local" if local else "official", "interval": interval})
        previous, segment = None, 0
        from itertools import chain
        for index, item in enumerate(chain(prefix, iterator), 1):
            if cancelled(): raise InterruptedError("导入已取消")
            if previous is not None and item.time < previous:
                raise ValueError(f"第 {index} 条时间倒退")
            if not local:
                if previous is not None and item.time - previous > max(2, 5 * interval): segment += 1
                item = replace(item, segment=segment)
            previous = item.time
            recording.append(item)
        recording.close()
        return {"path": str(destination), "count": recording.count}
    except BaseException:
        if recording:
            try: recording.close(False)
            finally:
                for suffix in ("", "-wal", "-shm"): Path(str(destination) + suffix).unlink(missing_ok=True)
        raise
    finally:
        iterator.close()


def export_record(source, destination, kind, start=None, end=None, cancelled=lambda: False):
    if kind not in ("csv", "official-sqlite", "local-sqlite"): raise ValueError("导出格式无效")
    source, destination = Path(source).resolve(strict=True), Path(destination).resolve()
    if source == destination: raise ValueError("导出不能覆盖正在读取的记录")
    db = readonly(source)
    temporary = None
    target = None
    try:
        validate_local(db)
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix=".k2-export-", dir=destination.parent)
        os.close(fd); temporary = Path(name)
        if kind == "local-sqlite":
            target = sqlite3.connect(temporary)
            def progress(*_):
                if cancelled(): raise InterruptedError("导出已取消")
            db.backup(target, pages=256, progress=progress)
            if start is not None: target.execute("DELETE FROM samples WHERE time < ?", (start,))
            if end is not None: target.execute("DELETE FROM samples WHERE time > ?", (end,))
            target.execute("UPDATE metadata SET value='1' WHERE key='closed'")
            target.commit()
            target.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            target.execute("PRAGMA journal_mode=DELETE")
            target.close(); target = None
        else:
            clause, params = "", []
            if start is not None: clause += " AND time>=?"; params.append(start)
            if end is not None: clause += " AND time<=?"; params.append(end)
            count, first, last = db.execute("SELECT count(*),min(time),max(time) FROM samples WHERE 1" + clause, params).fetchone()
            info = metadata(db)
            interval = number(info.get("interval"), True)
            rate = number(info.get("rate"), True)
            interval = interval or (1 / rate if rate else 0)
            info = dict(zip(KEYS, (str(count), elapsed_text((last or 0) - (first or 0)), str(round(interval * 1000)), info.get("DateTime", ""))))
            def values():
                for s in samples(db, start, end):
                    if cancelled(): raise InterruptedError("导出已取消")
                    yield (elapsed_text(s.time), s.voltage, s.current, abs(s.power), s.temp_out, s.dp, s.dn)
            if kind == "csv":
                with temporary.open("w", encoding="utf-8-sig", newline="") as stream:
                    writer = csv.writer(stream)
                    writer.writerows(info.items()); writer.writerow([]); writer.writerow(OFFICIAL)
                    for row in values(): writer.writerow(('="' + row[0] + '"',) + row[1:])
            else:
                target = sqlite3.connect(temporary)
                target.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)")
                target.executemany("INSERT INTO metadata VALUES(?,?)", info.items())
                target.execute("CREATE TABLE records(id INTEGER PRIMARY KEY AUTOINCREMENT," + ",".join('"' + c + '" TEXT' for c in OFFICIAL) + ")")
                target.executemany("INSERT INTO records(" + ",".join('"' + c + '"' for c in OFFICIAL) + ") VALUES(?,?,?,?,?,?,?)", values())
                target.commit(); target.close(); target = None
        if cancelled(): raise InterruptedError("导出已取消")
        os.replace(temporary, destination); temporary = None
        return {"path": str(destination)}
    finally:
        if target: target.close()
        db.close()
        if temporary: temporary.unlink(missing_ok=True)
