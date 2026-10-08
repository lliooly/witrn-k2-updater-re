#!/usr/bin/env python3
"""Freeze the helper from a project-local build environment, including HID."""
import argparse
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", default="universal2", choices=("universal2", "arm64", "x86_64"))
    args = parser.parse_args()
    if args.arch == "universal2":
        extension = Path(importlib.util.find_spec("hid").origin)
        # A previously interrupted merge can leave an invalid Mach-O signature.
        run("/usr/bin/codesign", "--force", "--sign", "-", extension)
        architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(extension)], text=True).split()
        if not {"arm64", "x86_64"}.issubset(architectures):
            wheels = ROOT / "build/wheels"
            wheels.mkdir(parents=True, exist_ok=True)
            if not list(wheels.glob("hidapi-0.15.0-*x86_64.whl")):
                run(sys.executable, "-m", "pip", "download", "--only-binary=:all:", "--no-deps",
                    "--platform", "macosx_13_0_x86_64", "--python-version", "39", "--implementation", "cp",
                    "--abi", "cp39", "hidapi==0.15.0", "--dest", wheels)
            wheel = next(wheels.glob("hidapi-0.15.0-*x86_64.whl"))
            with zipfile.ZipFile(wheel) as archive:
                entry = next(n for n in archive.namelist() if n.endswith(".so") and Path(n).name == extension.name)
                intel = ROOT / "build/hid-intel.so"
                intel.write_bytes(archive.read(entry))
            combined = ROOT / "build/hid-universal2.so"
            run("/usr/bin/lipo", "-create", extension, intel, "-output", combined)
            run("/usr/bin/codesign", "--force", "--sign", "-", combined)
            shutil.copy2(combined, extension)
        run("/usr/bin/codesign", "--force", "--sign", "-", extension)
        # Validation includes a real import under each architecture.
        for architecture in ("arm64", "x86_64"):
            run("/usr/bin/arch", f"-{architecture}", sys.executable, "-c", "import hid; print('HID import OK')")
    run(sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir",
        "--name", "k2-backend", "--target-arch", args.arch,
        "--distpath", ROOT / "build/backend-dist", "--workpath", ROOT / "build/pyinstaller",
        "--specpath", ROOT / "build", "--hidden-import", "hid",
        "--add-data", str(ROOT / "k2up/data/firmware_decode.bin") + ":k2up/data",
        ROOT / "k2_gui_backend.py")


if __name__ == "__main__":
    main()
