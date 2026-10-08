#!/usr/bin/env python3
"""Stage and locally sign the .app; never bundle personal or vendor data."""
import argparse
import importlib.metadata
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--arch", default="universal2")
    args = parser.parse_args()
    app = ROOT / "dist/K2 Updater.app"
    # This is our generated build output only, never user-selected paths.
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    macos, resources = contents / "MacOS", contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(args.binary, macos / "K2Updater")
    helper = ROOT / "build/backend-dist/k2-backend"
    shutil.copytree(helper, resources / "Backend", symlinks=True)
    for name in ("LICENSE", "NOTICE.md"):
        if (ROOT / name).exists():
            shutil.copy2(ROOT / name, resources / name)
    licenses = resources / "ThirdPartyLicenses"
    licenses.mkdir()
    shutil.copy2(Path(sys.base_prefix) / "lib/python3.9/LICENSE.txt", licenses / "Python-LICENSE.txt")
    for dependency in ("hidapi", "pyinstaller"):
        distribution = importlib.metadata.distribution(dependency)
        for entry in distribution.files or []:
            if ".dist-info/licenses/" in str(entry):
                destination = licenses / dependency / Path(entry).name
                destination.parent.mkdir(exist_ok=True)
                shutil.copy2(distribution.locate_file(entry), destination)
    icon = ROOT / "build/K2Updater.icns"
    if icon.exists():
        shutil.copy2(icon, resources / icon.name)
    info = {
        "CFBundleExecutable": "K2Updater", "CFBundleIdentifier": "dev.witrn.k2updater",
        "CFBundleName": "K2 Updater", "CFBundleDisplayName": "WITRN K2",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.3.0",
        "CFBundleVersion": "4", "LSMinimumSystemVersion": "13.0",
        "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True,
        "CFBundleDevelopmentRegion": "zh_CN",
        "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "dev.witrn.k2-firmware",
                                        "UTTypeDescription": "K2 Firmware", "UTTypeConformsTo": ["public.data"],
                                        "UTTypeTagSpecification": {"public.filename-extension": ["k2"]}},
                                       {"UTTypeIdentifier": "dev.witrn.k2-project", "UTTypeDescription": "K2 表盘工程",
                                        "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": {"public.filename-extension": ["k2project"]}},
                                       {"UTTypeIdentifier": "dev.witrn.k2-picture", "UTTypeDescription": "K2 表盘布局",
                                        "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": {"public.filename-extension": ["pic"]}}]
    }
    if icon.exists():
        info["CFBundleIconFile"] = icon.name
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    # Sign nested Mach-O code first, then their framework and app containers.
    binaries = []
    for path in resources.rglob("*"):
        if path.is_file() and not path.is_symlink():
            kind = subprocess.check_output(["/usr/bin/file", "-b", str(path)], text=True)
            if "Mach-O" in kind:
                binaries.append(path)
    for path in binaries:
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(path)], check=True)
    for framework in sorted(resources.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(framework)], check=True)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
    print(app)


if __name__ == "__main__":
    main()
