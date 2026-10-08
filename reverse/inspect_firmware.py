"""Offline K2 container inspection. This module has no USB or flashing code."""
import argparse
from datetime import date
from functools import reduce
import hashlib
import json
from pathlib import Path
import struct
import uuid

ROOT = Path(__file__).resolve().parent
HEADER_SIZE = 48
APP_START = 0x08003800  # K2 config copied into device field used by file writer.
K2_GUID = uuid.UUID('5a3f8522-366b-46cc-aacc-dbfbe2fee02a')


def inspect(raw: bytes):
    table = (ROOT / 'tables/firmware_decode.bin').read_bytes()
    if len(table) != 256 or len(set(table)) != 256:
        raise ValueError('Invalid decoding table')
    if len(raw) < HEADER_SIZE:
        raise ValueError('File is shorter than the 48-byte header')
    decoded = raw.translate(table)
    year, month, day = struct.unpack_from('<HBB', decoded, 7)
    model = uuid.UUID(bytes_le=decoded[20:36])
    length, expected_xor, expected_sum = struct.unpack_from('<III', decoded, 36)
    app = decoded[HEADER_SIZE:]
    actual_xor = reduce(int.__xor__, app, 0)
    actual_sum = sum(app) & 0xFFFFFFFF
    checks = {
        'magic': decoded[:7] == b'gzutapp',
        'k2_model_guid': model == K2_GUID,
        'payload_length': length == len(app),
        'payload_xor': expected_xor == actual_xor,
        'payload_sum': expected_sum == actual_sum,
        # Vendor checker only tests year <2050, month <13, day <32.
        'vendor_date_upper_bounds': year < 2050 and month < 13 and day < 32,
    }
    try:
        date_text = date(year, month, day).isoformat()
    except ValueError:
        date_text = None
    sectors = (ROOT / 'tables/k2_sector_kib.bin').read_bytes()
    covered = sector_count = 0
    for size_kib in sectors:
        if covered >= len(app):
            break
        covered += size_kib * 1024
        sector_count += 1
    checks['fits_configured_app_sectors'] = covered >= len(app)
    version = app[2048] if len(app) > 2048 else None
    vectors = struct.unpack_from('<8I', app) if len(app) >= 32 else None
    result = {
        'valid_container': all(checks.values()),
        'checks': checks,
        'source_sha256': hashlib.sha256(raw).hexdigest(),
        'source_size': len(raw),
        'header': {
            'magic': decoded[:7].decode('ascii', errors='replace'),
            'year': year, 'month': month, 'day': day, 'date': date_text,
            'reserved_hex': decoded[11:20].hex(), 'model_guid': str(model),
            'payload_size': length,
            'xor_u32': expected_xor, 'sum_u32': expected_sum,
        },
        'payload_size': len(app),
        'payload_sha256': hashlib.sha256(app).hexdigest(),
        'payload_xor': actual_xor, 'payload_sum': actual_sum,
        'version_byte_at_payload_0x800': version,
        'version': f'{version >> 4}.{version & 15}' if version is not None else None,
        'vector_words': [f'0x{x:08X}' for x in vectors] if vectors else None,
        'app_start_from_updater_config': f'0x{APP_START:08X}',
        'app_end_exclusive': f'0x{APP_START + len(app):08X}',
        'sector_rounding': {
            'count': sector_count, 'covered_bytes': covered,
            'end_exclusive': f'0x{APP_START + covered:08X}',
            'note': 'Derived from configured sectors; not a verified erase plan.',
        },
    }
    return result, decoded, app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('firmware', type=Path)
    parser.add_argument('--output-dir', type=Path,
                        help='Export decoded container, app image and inspection JSON')
    args = parser.parse_args()
    try:
        result, decoded, app = inspect(args.firmware.read_bytes())
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result['valid_container']:
        parser.exit(1, 'Container validation failed; no decoded files exported.\n')
    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        stem = args.firmware.stem
        (args.output_dir / f'{stem}.decoded.bin').write_bytes(decoded)
        (args.output_dir / f'{stem}.app.bin').write_bytes(app)
        (args.output_dir / f'{stem}.json').write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
