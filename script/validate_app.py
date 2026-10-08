#!/usr/bin/env python3
"""Validate a relocated bundle and both frozen helpers without USB writes."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    source = args.app.resolve()
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    binaries = []
    for path in source.rglob("*"):
        if path.is_file() and not path.is_symlink():
            if "Mach-O" in subprocess.check_output(["/usr/bin/file", "-b", str(path)], text=True):
                architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(path)], text=True).split()
                if not {"arm64", "x86_64"}.issubset(architectures):
                    raise RuntimeError(f"Missing architecture: {path}")
                binaries.append(path)
    with tempfile.TemporaryDirectory(prefix="k2-app-validation-") as temp:
        root = Path(temp)
        app = root / "K2 Updater.app"
        shutil.copytree(source, app, symlinks=True)
        helper = app / "Contents/Resources/Backend/k2-backend"
        for architecture in ("arm64", "x86_64"):
            def request(operation, **fields):
                data = {"id": str(uuid.uuid4()), "operation": operation, "simulation": True,
                        "data_directory": str(root / architecture), "demo_delay_ms": 0, **fields}
                process = subprocess.run(["/usr/bin/arch", f"-{architecture}", str(helper)],
                                         input=json.dumps(data) + "\n", text=True, capture_output=True,
                                         cwd=root, env={"PATH": "/usr/bin:/bin"}, timeout=60)
                if process.returncode:
                    raise RuntimeError(process.stdout + process.stderr)
                events = [json.loads(line) for line in process.stdout.splitlines()]
                if not events or events[-1]["event"] != "result":
                    raise RuntimeError("Helper returned no successful result")
                return events[-1]["value"]
            # Loads hidapi under each architecture, enumeration only.
            request("devices", simulation=False)
            csv = root / (architecture + "-record.csv")
            csv.write_text('Time(D.hh:mm:ss.ms),Voltage(V),Current(A)\n00:00:00.000,5,-2\n00:00:01.000,5,2\n', encoding="utf-8")
            imported = request("monitor-import", record_path=str(csv), output_path=str(root / (architecture + "-record.sqlite")))
            analysis = request("monitor-query", record_path=imported["path"])
            assert analysis["count"] == 2 and analysis["statistics"]["wh_net"] == 0
            for kind in ("csv", "official-sqlite", "local-sqlite"):
                exported = request("monitor-export", record_path=imported["path"], output_path=str(root / (architecture + "-" + kind)), export_kind=kind)
                recovered = request("monitor-import", record_path=exported["path"], output_path=str(root / (architecture + "-" + kind + "-recovered.sqlite")))
                assert recovered["count"] == 2
            firmware = request("demo-firmware")
            identity = request("probe")["identity"]
            result = request("upgrade", firmware_path=firmware["firmware_path"],
                             firmware_sha256=firmware["firmware"]["file_sha256"],
                             device_info_sha256=identity["info_sha256"], confirmed=True)
            assert result["simulation_only"] and result["backup"]["simulation_only"]
            assert result["backup"]["two_independent_reads_match"]
            for kind in ("layout", "background", "startup", "emark", "emark-copy"):
                read = request("resource-read", resource_kind=kind)
                assert read["simulation_only"] and read["resource_valid"] and read["backup"]["two_reads_match"]
                from hashlib import sha256
                resource_path = Path(read["resource_path"])
                write = request("resource-write", resource_kind=kind, resource_path=str(resource_path),
                                resource_sha256=sha256(resource_path.read_bytes()).hexdigest(),
                                device_info_sha256=read["identity"]["info_sha256"], confirmed=True)
                manifest = Path(write["backup"]["directory"]) / "manifest.json"
                restored = request("resource-restore", resource_kind=kind, restore_manifest_path=str(manifest),
                                   restore_manifest_sha256=sha256(manifest.read_bytes()).hexdigest(),
                                   device_info_sha256=read["identity"]["info_sha256"], confirmed=True)
                assert restored["simulation_only"] and restored["verified_sha256"]
            print(f"{architecture}: relocated helper, HID/SQLite load, curve query/exchange, firmware and all resource simulations OK")
    print(f"Bundle signature OK; {len(binaries)} Mach-O files include both architectures")


if __name__ == "__main__":
    main()
