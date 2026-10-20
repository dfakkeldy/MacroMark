import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "ios_simulator.py"


class SimulatorBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "Provision an iPhone instead of skipping app-hosted tests")
        spec = importlib.util.spec_from_file_location("ios_simulator", SCRIPT)
        self.bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.bootstrap)

    def test_newest_available_ios_runtime_is_selected(self):
        rows = [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "version": "26.2", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": False},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.watchOS-27-0", "version": "27.0", "isAvailable": True},
        ]
        self.assertEqual(self.bootstrap.ios_runtime(rows)["version"], "26.5")

    def test_existing_device_selection_excludes_ipads_and_unavailable_phones(self):
        rows = [
            {"udid": "ipad", "name": "iPad", "isAvailable": True},
            {"udid": "bad", "name": "iPhone 17", "isAvailable": False},
            {"udid": "phone", "name": "iPhone 16e", "isAvailable": True},
        ]
        self.assertEqual(self.bootstrap.iphone(rows)["udid"], "phone")

    def test_preview_runtime_from_another_xcode_is_not_selected(self):
        rows = [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": True},
        ]
        self.assertEqual(self.bootstrap.ios_runtime(rows, "26.5")["version"], "26.5")

    def test_device_type_must_support_the_installed_runtime(self):
        rows = [
            {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-5s", "maxRuntimeVersionString": "12.5.7"},
            {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "minRuntimeVersionString": "26.0.0"},
            {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18", "minRuntimeVersionString": "27.0.0"},
        ]
        self.assertEqual(self.bootstrap.iphone_type(rows, "26.5")["identifier"],
                         "com.apple.CoreSimulator.SimDeviceType.iPhone-17")

    def run_cli(self, download_needed=False, download_fails=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake = root / "xcrun"
            fake.write_text("#!" + sys.executable + "\n" + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args == ["--sdk", "iphonesimulator", "--show-sdk-version"]:
    print('26.5')
elif args == ["simctl", "list", "runtimes", "--json"]:
    ready = not os.environ.get("NEEDS_DOWNLOAD") or Path(os.environ["DOWNLOADED"]).exists()
    print(json.dumps({"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "isAvailable": bool(ready)}]}))
elif args == ["simctl", "list", "devices", "available", "--json"]:
    print('{"devices": {}}')
elif args == ["simctl", "list", "devicetypes", "--json"]:
    print('{"devicetypes": [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "name": "iPhone 17", "minRuntimeVersionString": "26.0.0"}]}')
elif args == ["simctl", "create", "MacroMark CI", "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"]:
    print('created-phone')
else:
    raise SystemExit("Unexpected simulator command: " + repr(args))
''')
            fake.chmod(0o755)
            download = root / "xcodebuild"
            download.write_text("#!" + sys.executable + "\n" + '''import os, sys
from pathlib import Path
assert sys.argv[1:] == ["-downloadPlatform", "iOS", "-buildVersion", "26.5"]
if not os.environ.get("DOWNLOAD_FAILS"):
    Path(os.environ["DOWNLOADED"]).touch()
''')
            download.chmod(0o755)
            output = root / "outputs"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       GITHUB_OUTPUT=str(output), DOWNLOADED=str(root / "downloaded"))
            if download_needed:
                env["NEEDS_DOWNLOAD"] = "true"
            if download_fails:
                env["DOWNLOAD_FAILS"] = "true"
            result = subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)
            return result, output.read_text() if output.exists() else ""

    def test_empty_host_creates_a_phone_and_outputs_a_real_destination(self):
        result, output = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("can_test=true\n", output)
        self.assertIn("ios_destination=platform=iOS Simulator,id=created-phone\n", output)

    def test_missing_runtime_is_provisioned_before_creating_the_phone(self):
        result, output = self.run_cli(download_needed=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ios_udid=created-phone\n", output)

    def test_runtime_unavailable_after_download_fails_without_test_outputs(self):
        result, output = self.run_cli(download_needed=True, download_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")
