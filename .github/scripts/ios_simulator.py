#!/usr/bin/env python3
"""Select or provision an iPhone on a hosted runner before app-hosted tests."""

import json
import os
import subprocess
import sys


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return (parts + (0, 0, 0))[:3]


def ios_runtime(rows, sdk_version=None):
    available = [row for row in rows if row.get("isAvailable")
                 and row["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                 and (sdk_version is None or version(row["version"]) <= version(sdk_version))]
    return max(available, key=lambda row: version(row["version"]), default=None)


def iphone(rows):
    return next((row for row in rows if row.get("isAvailable")
                 and (row.get("name", "").startswith("iPhone")
                      or row.get("deviceTypeIdentifier", "").startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-")
                      or row.get("name") == "MacroMark CI")), None)


def iphone_type(rows, runtime_version):
    current = version(runtime_version)
    compatible = [row for row in rows
                  if row["identifier"].startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-")
                  and version(row.get("minRuntimeVersionString", "0")) <= current
                  and version(row.get("maxRuntimeVersionString", "999")) >= current]
    if not compatible:
        raise ValueError("No iPhone device type supports the installed iOS runtime")
    return compatible[-1]


def simctl_json(*args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", *args, "--json"], text=True))


def main():
    sdk_version = subprocess.check_output([
        "xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"
    ], text=True).strip()
    runtime = ios_runtime(simctl_json("runtimes")["runtimes"], sdk_version)
    if runtime is None:
        subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", sdk_version], check=True)
        runtime = ios_runtime(simctl_json("runtimes")["runtimes"], sdk_version)
    if runtime is None:
        raise ValueError("No available iOS simulator runtime after platform provisioning")

    devices = simctl_json("devices", "available")["devices"].get(runtime["identifier"], [])
    device = iphone(devices)
    if device:
        udid, name = device["udid"], device["name"]
    else:
        device_type = iphone_type(simctl_json("devicetypes")["devicetypes"], runtime["version"])
        udid = subprocess.check_output([
            "xcrun", "simctl", "create", "MacroMark CI", device_type["identifier"], runtime["identifier"]
        ], text=True).strip()
        name = "MacroMark CI"
    if not udid:
        raise ValueError("Simulator provisioning returned no device identifier")

    with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
        handle.write(f"can_test=true\nios_udid={udid}\nios_device={name}\n"
                     f"ios_destination=platform=iOS Simulator,id={udid}\n")
    print(f"iOS {runtime['version']}: {name} ({udid})")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"::error::iOS simulator setup failed: {error}", file=sys.stderr)
        sys.exit(1)
