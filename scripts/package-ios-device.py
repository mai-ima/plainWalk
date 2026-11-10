#!/usr/bin/env python3
"""Verify and package an actual unsigned iPhoneOS build; never a Simulator app."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

IPA_NAME = "PlainWalk-iPhone-unsigned.ipa"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def run(*command: str) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    require(result.returncode == 0, f"Command failed: {' '.join(command)}\n{result.stderr.strip()}")
    return result.stdout


def inspect_binary(binary: Path) -> dict:
    require(binary.is_file(), f"Missing bundle executable: {binary}")
    architectures = run("xcrun", "lipo", "-archs", str(binary)).strip().split()
    require("arm64" in architectures and set(architectures) <= {"arm64", "arm64e"},
            f"Expected an ARM64 iPhone binary, found {architectures}: {binary}")
    versions = []
    for architecture in architectures:
        output = run("xcrun", "vtool", "-arch", architecture, "-show-build", str(binary))
        require("LC_BUILD_VERSION" in output, f"No LC_BUILD_VERSION proof: {binary}")
        platforms = re.findall(r"^\s*platform\s+(\S+)", output, re.MULTILINE)
        require(platforms and all(value in {"IOS", "2"} for value in platforms),
                f"Executable is not built for iOS devices: {platforms}: {binary}")
        minimums = re.findall(r"^\s*minos\s+(\S+)", output, re.MULTILINE)
        require(minimums, f"Missing minimum iOS load-command version: {binary}")
        versions.extend(minimums)
    return {"architectures": architectures, "loadCommand": "LC_BUILD_VERSION", "platform": "IOS", "minimumOSVersions": versions}


def inspect_signature(bundle: Path) -> str:
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)], capture_output=True, text=True, check=False)
    output = result.stdout + result.stderr
    require(not re.search(r"^Authority=", output, re.MULTILINE), f"A certificate signing authority was found: {bundle}")
    teams = re.findall(r"^TeamIdentifier=(.+)$", output, re.MULTILINE)
    require(all(team.strip() == "not set" for team in teams), f"Unexpected signing team: {bundle}")
    if result.returncode != 0:
        require("not signed at all" in output, f"Unable to verify unsigned state: {bundle}\n{output.strip()}")
        return "not-signed"
    require("Signature=adhoc" in output, f"Expected no signature or an ad hoc linker signature: {bundle}")
    return "ad-hoc"


def inspect_bundle(bundle: Path, *, device_family: bool = True) -> dict:
    info_path = bundle / "Info.plist"
    require(info_path.is_file(), f"Missing processed Info.plist: {bundle}")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"],
            f"Not an iPhoneOS bundle: {bundle}")
    if device_family:
        require(1 in info.get("UIDeviceFamily", []), f"Bundle does not support iPhone: {bundle}")
    identifier = info.get("CFBundleIdentifier")
    executable = info.get("CFBundleExecutable")
    require(isinstance(identifier, str) and identifier and "$" not in identifier, f"Unresolved bundle ID: {bundle}")
    require(isinstance(executable, str) and executable and Path(executable).name == executable,
            f"Invalid executable name: {bundle}")
    binary = bundle / executable
    require(binary.resolve().is_relative_to(bundle.resolve()), f"Executable escapes its bundle: {bundle}")
    minimum = info.get("MinimumOSVersion")
    require(isinstance(minimum, str) and re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum),
            f"Missing processed minimum iOS version: {bundle}")
    return {"bundleIdentifier": identifier, "executable": executable, "minimumIOS": minimum,
            "binary": inspect_binary(binary), "codeSignature": inspect_signature(bundle)}


def add_entry(archive: zipfile.ZipFile, path: Path, name: str, app: Path) -> None:
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        require(path.resolve().is_relative_to(app.resolve()), f"Bundle symlink escapes the app: {path}")
        entry = zipfile.ZipInfo(name)
        entry.create_system = 3
        entry.external_attr = mode << 16
        archive.writestr(entry, os.readlink(path).encode("utf-8"))
    else:
        require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), f"Unsupported bundle file type: {path}")
        archive.write(path, name)


def package(app: Path, output: Path, source_commit: str) -> dict:
    require(app.name == "PlainWalk.app" and app.is_dir() and not app.is_symlink(), "Pass the compiled PlainWalk.app directory.")
    require(re.fullmatch(r"[a-fA-F0-9]{40}", source_commit) is not None, "source-commit must be a full 40-character Git SHA.")
    require(not list(app.rglob("embedded.mobileprovision")), "A provisioning profile was found; this package must remain unsigned.")
    main = inspect_bundle(app)
    extensions = []
    for extension in sorted((app / "PlugIns").glob("*.appex")):
        item = inspect_bundle(extension)
        require(item["bundleIdentifier"].startswith(main["bundleIdentifier"] + "."), f"Extension ID is not bound to the app: {extension}")
        extensions.append(item)
    require(any(item["bundleIdentifier"] == main["bundleIdentifier"] + ".Live" for item in extensions),
            "The compiled Live Activity extension is missing.")
    frameworks = []
    for framework in sorted(app.rglob("*.framework")):
        frameworks.append(inspect_bundle(framework, device_family=False))
    output.mkdir(parents=True, exist_ok=True)
    destination = output / IPA_NAME
    with tempfile.NamedTemporaryFile(dir=output, suffix=".ipa.tmp", delete=False) as handle:
        temporary = Path(handle.name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            archive.writestr("Payload/", b"")
            add_entry(archive, app, "Payload/PlainWalk.app/", app)
            for directory, folders, files in os.walk(app, followlinks=False):
                root = Path(directory)
                folders.sort(); files.sort()
                for name in folders + files:
                    path = root / name
                    entry = "Payload/PlainWalk.app/" + path.relative_to(app).as_posix()
                    if path.is_dir() and not path.is_symlink():
                        entry += "/"
                    add_entry(archive, path, entry, app)
                folders[:] = [name for name in folders if not (root / name).is_symlink()]
        with zipfile.ZipFile(temporary) as archive:
            require(archive.testzip() is None, "IPA failed ZIP CRC verification.")
            require(all(name.startswith("Payload/") and ".." not in Path(name).parts for name in archive.namelist()), "Unexpected archive root or traversal entry.")
            require("Payload/PlainWalk.app/Info.plist" in archive.namelist(), "App bundle was not packaged.")
        sha256 = hashlib.sha256(temporary.read_bytes()).hexdigest()
        temporary.replace(destination)
        require(hashlib.sha256(destination.read_bytes()).hexdigest() == sha256, "IPA hash changed during publication.")
    finally:
        temporary.unlink(missing_ok=True)
    metadata = {
        "filename": IPA_NAME, "sourceCommit": source_commit.lower(),
        "platform": "iPhoneOS", "architecture": "arm64", "minimumIOS": main["minimumIOS"],
        "signing": "unsigned", "requiresSigning": True, "installableAsDownloaded": False,
        "sha256": sha256, "bytes": destination.stat().st_size,
        "bundleIdentifier": main["bundleIdentifier"],
        "extensionBundleIdentifiers": [item["bundleIdentifier"] for item in extensions],
        "app": main, "extensions": extensions, "frameworks": frameworks,
        "verification": {"deviceLoadCommands": True, "noProvisioningProfile": True,
                         "noCertificateSigningAuthority": True, "zipCRC": True, "sha256": True},
    }
    (output / "PlainWalk-iPhone-unsigned.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    (output / "PlainWalk-iPhone-unsigned.sha256").write_text(f"{sha256}  {IPA_NAME}\n")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    try:
        metadata = package(args.app.resolve(), args.output_dir.resolve(), args.source_commit)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Device package rejected: {error}\n")
    print(json.dumps({key: metadata[key] for key in ("filename", "sha256", "bytes", "platform", "architecture", "signing", "installableAsDownloaded")}))


if __name__ == "__main__":
    main()
