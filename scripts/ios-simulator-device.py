"""Select one iPhone Simulator and reuse the workflow's warmed device."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid


def validated_device(udid, name):
    if not isinstance(udid, str) or not isinstance(name, str) or not name.strip():
        raise ValueError("Simulator selection requires a UUID and a device name.")
    try:
        parsed = uuid.UUID(udid)
    except ValueError as error:
        raise ValueError("Simulator device UUID is invalid: " + udid) from error
    if str(parsed) != udid.lower():
        raise ValueError("Simulator device UUID must use the standard hyphenated form.")
    if "\n" in name or "\r" in name:
        raise ValueError("Simulator device name must fit on one line.")
    return {"udid": udid, "name": name}


def select_device():
    cached_udid = os.environ.get("PW_SIM_DEVICE")
    cached_name = os.environ.get("PW_SIM_DEVICE_NAME")
    if cached_udid is not None or cached_name is not None:
        return validated_device(cached_udid, cached_name)
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, timeout=90, check=True,
    )
    devices = json.loads(result.stdout)
    for group in devices["devices"].values():
        for device in group:
            if "iPhone" in device.get("name", "") and device.get("isAvailable"):
                return validated_device(device.get("udid"), device["name"])
    raise ValueError("No available iPhone Simulator runtime was found.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--json", action="store_true", help="Print the selected UUID and name as JSON.")
    output.add_argument("--export-github-env", action="store_true", help="Save the selection for later GitHub Actions steps.")
    args = parser.parse_args()
    try:
        device = select_device()
        if args.export_github_env:
            env_file = os.environ.get("GITHUB_ENV")
            if not env_file:
                raise ValueError("--export-github-env requires GITHUB_ENV.")
            with Path(env_file).open("a", encoding="utf-8") as stream:
                stream.write("PW_SIM_DEVICE=" + device["udid"] + "\n")
                stream.write("PW_SIM_DEVICE_NAME=" + device["name"] + "\n")
        print(json.dumps(device) if args.json else device["udid"])
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        print("Could not select an iPhone Simulator: " + detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
