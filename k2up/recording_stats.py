"""Streaming original-point integration and bounded extrema-preserving plots."""
import math

from .recording import metadata, readonly, samples, summary, validate_local

CHANNELS = ("voltage", "current", "power", "temp_in", "temp_out", "dp", "dn")


def direction_area(a, b, dt):
    """Positive and negative magnitudes for a line, split exactly at zero."""
    if a >= 0 and b >= 0: return (a + b) * dt / 2, 0
    if a <= 0 and b <= 0: return 0, -(a + b) * dt / 2
    first = dt * abs(a) / (abs(a) + abs(b))
    area_a, area_b = abs(a) * first / 2, abs(b) * (dt - first) / 2
    return (area_a, area_b) if a > 0 else (area_b, area_a)


def interpolate(a, b, t):
    f = (t - a.time) / (b.time - a.time)
    values = a.dictionary()
    for name in CHANNELS + ("signed_power",):
        av, bv = getattr(a, name), getattr(b, name)
        values[name] = av + (bv - av) * f if av is not None and bv is not None else None
    values["time"] = t
    # Absolute derived power is piecewise linear through a sign change.
    values["power"] = abs(values["signed_power"])
    return type(a)(**values)


def statistics(items, start=None, end=None, gap_limit=2, cancelled=lambda: False):
    channel = {k: {"min": None, "max": None, "area": 0., "coverage": 0.} for k in CHANNELS}
    count, coverage = 0, 0.
    ah_pos = ah_neg = wh_pos = wh_neg = 0.
    previous = None
    first = last = None
    def observe(s):
        for key, result in channel.items():
            v = getattr(s, key)
            if v is None: continue
            result["min"] = min(result["min"], v) if result["min"] is not None else v
            result["max"] = max(result["max"], v) if result["max"] is not None else v
    for s in items:
        if cancelled(): raise InterruptedError("统计已取消")
        if (start is None or s.time >= start) and (end is None or s.time <= end):
            count += 1; observe(s)
            first = s.time if first is None else first; last = s.time
        a, b = previous, s
        previous = s
        if a is None or a.segment != b.segment or not 0 < b.time - a.time <= gap_limit: continue
        lo, hi = max(a.time, start if start is not None else a.time), min(b.time, end if end is not None else b.time)
        if hi <= lo: continue
        left, right = interpolate(a, b, lo), interpolate(a, b, hi)
        observe(left); observe(right)
        if left.signed_power * right.signed_power < 0:
            channel["power"]["min"] = 0
        first = lo if first is None else min(first, lo); last = hi if last is None else max(last, hi)
        dt = hi - lo; coverage += dt
        for key, result in channel.items():
            av, bv = getattr(left, key), getattr(right, key)
            if av is not None and bv is not None:
                if key == "power":
                    positive, negative = direction_area(left.signed_power, right.signed_power, dt)
                    result["area"] += positive + negative
                else: result["area"] += (av + bv) * dt / 2
                result["coverage"] += dt
        positive, negative = direction_area(left.current, right.current, dt)
        ah_pos += positive / 3600; ah_neg += negative / 3600
        positive, negative = direction_area(left.signed_power, right.signed_power, dt)
        wh_pos += positive / 3600; wh_neg += negative / 3600
    for result in channel.values():
        result["average"] = result.pop("area") / result["coverage"] if result["coverage"] else result["min"]
    return {"count": count, "span": (last - first) if first is not None else 0, "coverage": coverage,
            "channels": channel, "ah_positive": ah_pos, "ah_negative": ah_neg, "ah_absolute": ah_pos + ah_neg,
            "ah_net": ah_pos - ah_neg, "wh_positive": wh_pos, "wh_negative": wh_neg,
            "wh_absolute": wh_pos + wh_neg, "wh_net": wh_pos - wh_neg}


def plot_points(items, start, end, budget=6000, cancelled=lambda: False):
    bucket_count = max(1, budget // (2 * len(CHANNELS) + 2))
    width = max(end - start, 1e-9) / bucket_count
    result, active, choices = [], None, {}
    def flush():
        selected = {s.time: s for s in choices.values()}
        result.extend(selected[t].dictionary() for t in sorted(selected))
    for s in items:
        if cancelled(): raise InterruptedError("查询已取消")
        key = min(bucket_count - 1, int((s.time - start) / width))
        if active is not None and key != active:
            flush(); choices = {}
        active = key
        choices.setdefault("first", s); choices["last"] = s
        for name in CHANNELS:
            value = getattr(s, name)
            if value is None: continue
            for kind, compare in (("min", lambda a, b: a < b), ("max", lambda a, b: a > b)):
                identity = name + kind
                if identity not in choices or compare(value, getattr(choices[identity], name)):
                    choices[identity] = s
    if choices: flush()
    return result


def query_record(path, start=None, end=None, include_stats=True, cancelled=lambda: False, budget=6000):
    info = summary(path)
    if not info["count"]: return {**info, "points": [], "statistics": None}
    lo = info["start"] if start is None else max(info["start"], float(start))
    hi = info["end"] if end is None else min(info["end"], float(end))
    if not math.isfinite(lo) or not math.isfinite(hi) or lo > hi: raise ValueError("区间起止时间无效")
    db = readonly(path)
    try:
        validate_local(db)
        points = plot_points(samples(db, lo, hi), lo, hi, budget=budget, cancelled=cancelled)
        result = {**info, "points": points, "range_start": lo, "range_end": hi}
        if include_stats:
            meta = metadata(db)
            rate = float(meta.get("rate", 0))
            interval = float(meta.get("interval", 1 / rate if rate else .01))
            gap_limit = max(2, 5 * interval)
            # One neighbor on either side is enough for exact boundary interpolation.
            left = db.execute("SELECT max(time) FROM samples WHERE time<?", (lo,)).fetchone()[0]
            right = db.execute("SELECT min(time) FROM samples WHERE time>?", (hi,)).fetchone()[0]
            selected = statistics(samples(db, left if left is not None else lo, right if right is not None else hi), lo, hi, gap_limit, cancelled)
            full = statistics(samples(db), gap_limit=gap_limit, cancelled=cancelled)
            selected["percentages"] = {key: selected[key] * 100 / full[key] if full[key] else None for key in ("coverage", "ah_absolute", "wh_absolute")}
            result.update(statistics=selected, full_statistics=full)
        return result
    finally:
        db.close()
