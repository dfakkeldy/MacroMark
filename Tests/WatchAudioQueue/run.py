#!/usr/bin/env python3
"""Run the watch LocalStore on Linux with adapters for unavailable Apple services.

Copies production source into a temporary Swift package, removing only imports
provided by Adapters.swift. No queue logic is replaced. Requires Swift 6.2+.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[1]
with tempfile.TemporaryDirectory(prefix="mm-watch-audio-") as directory:
    package = Path(directory)
    source = package / "Sources" / "WatchQueue"
    tests = package / "Tests" / "WatchQueueTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WatchQueue", targets: [
    .target(name: "WatchQueue"),
    .testTarget(name: "WatchQueueTests", dependencies: ["WatchQueue"])
])
''')
    files = [root / "MacroMark Watch App/Storage/LocalStore.swift"]
    kit = root / "MacroMarkKit/Sources/MacroMarkKit"
    files += [kit / name for name in ["Delivery/TextDeliveryQueue.swift",
        "Delivery/DirectSendConfiguration.swift", "Support/DaySelection.swift"]]
    for path in files:
        lines = path.read_text().splitlines(keepends=True)
        (source / path.name).write_text("".join(line for line in lines
            if line.strip() not in {"import MacroMarkKit", "import WidgetKit", "import os"}))
    shutil.copy(here / "Adapters.swift", source)
    shutil.copy(here / "AudioQueueTests.swift", tests)
    environment = dict(os.environ, XDG_DATA_HOME=str(package / "data"),
        XDG_CONFIG_HOME=str(package / "config"))
    subprocess.run(["swift", "test", "--package-path", str(package), "--disable-sandbox",
        "--build-system", "native", "--cache-path", str(package / "cache"), "--jobs", "2"],
        check=True, env=environment)
