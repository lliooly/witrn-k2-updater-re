"""Versioned local SQLite records. Bounded memory and explicit commit ownership."""
from dataclasses import fields
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
import time
import math

from .telemetry import Sample

COLUMNS = tuple(f.name for f in fields(Sample))
SQL_COLUMNS = ",".join('"' + name + '"' for name in COLUMNS)
SCHEMA = 1


def readonly(path):
    path = Path(path).expanduser().resolve(strict=True)
    db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
    db.execute("PRAGMA query_only=ON")
    db.execute("PRAGMA trusted_schema=OFF")
    db.row_factory = sqlite3.Row
    return db


def metadata(db):
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if "metadata" not in tables:
        return {}
    return {r[0]: r[1] for r in db.execute("SELECT key,value FROM metadata LIMIT 100")}


def validate_local(db):
    if metadata(db).get("k2_schema") != str(SCHEMA):
        raise ValueError("不是支持的本地记录版本")
    names = {r[1] for r in db.execute("PRAGMA table_info(samples)")}
    if not set(COLUMNS).issubset(names):
        raise ValueError("本地记录缺少必要字段")
    kind = db.execute("SELECT type FROM sqlite_master WHERE name='samples'").fetchone()
    if not kind or kind[0] != "table": raise ValueError("本地样本必须存放在数据表")


def samples(db, start=None, end=None):
    clauses, args = [], []
    for name, value in ((">=", start), ("<=", end)):
        if value is not None:
            clauses.append("time " + name + " ?"); args.append(value)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    for row in db.execute("SELECT " + SQL_COLUMNS + " FROM samples" + where + " ORDER BY time,id", args):
        yield Sample(**dict(row))


class Recording:
    def __init__(self, path, rate=10, extra=None):
        self.path = Path(path).expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Reserve without opening or truncating an existing database.
        with self.path.open("xb"):
            pass
        self.db = None
        try:
            self.db = sqlite3.connect(self.path)
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")
            self.db.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)")
            self.db.execute("CREATE TABLE samples(id INTEGER PRIMARY KEY," +
                            ",".join('"' + name + '"' + (" INTEGER" if name in ("segment", "group", "uptime", "record_seconds") else " REAL") for name in COLUMNS) + ")")
            self.db.execute("CREATE INDEX sample_time ON samples(time)")
            values = {"k2_schema": str(SCHEMA), "closed": "0", "rate": str(rate),
                      "DateTime": datetime.now(timezone.utc).isoformat(), "model": "K2", **(extra or {})}
            self.db.executemany("INSERT INTO metadata VALUES(?,?)", [(k, str(v)) for k, v in values.items()])
            self.db.commit()
        except BaseException:
            if self.db: self.db.close()
            self.path.unlink(missing_ok=True)
            raise
        self.pending = 0
        self.count = 0
        self.last_commit = time.monotonic()

    def append(self, sample):
        required = (sample.time, sample.voltage, sample.current, sample.power, sample.signed_power, sample.segment)
        try:
            valid = all(v is not None and math.isfinite(v) for v in required)
            valid = valid and all(math.isfinite(v) for v in sample.dictionary().values() if v is not None)
        except TypeError:
            valid = False
        if not valid or sample.time < 0 or sample.voltage < 0 or sample.segment < 0:
            raise ValueError("记录样本包含非法时间或数值")
        self.db.execute("INSERT INTO samples(" + SQL_COLUMNS + ") VALUES(" +
                        ",".join("?" for _ in COLUMNS) + ")", tuple(getattr(sample, name) for name in COLUMNS))
        self.pending += 1; self.count += 1
        if self.pending >= 100 or time.monotonic() - self.last_commit >= 1:
            self.commit()

    def commit(self):
        self.db.commit(); self.pending = 0; self.last_commit = time.monotonic()

    def close(self, complete=True):
        if self.db is None: return
        db = self.db
        try:
            if complete:
                db.execute("UPDATE metadata SET value='1' WHERE key='closed'")
            db.commit()
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        finally:
            db.close(); self.db = None


def summary(path):
    db = readonly(path)
    try:
        validate_local(db)
        count, start, end = db.execute("SELECT count(*),min(time),max(time) FROM samples").fetchone()
        return {"path": str(Path(path).resolve()), "count": count, "start": start, "end": end,
                "metadata": metadata(db)}
    finally:
        db.close()
