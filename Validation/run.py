"""Run the production FileTools implementation in an isolated Swift Testing package."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="mandarin-validation-") as directory:
    package = Path(directory)
    (package / "Sources/FileTools").mkdir(parents=True)
    (package / "Tests/FileToolsTests").mkdir(parents=True)
    shutil.copy2(root / "Mandarin/FileTools.swift", package / "Sources/FileTools/FileTools.swift")
    shutil.copy2(root / "Validation/FileToolsTests.swift", package / "Tests/FileToolsTests/FileToolsTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "FileTools", platforms: [.macOS(.v14)], targets: [
    .target(name: "FileTools"),
    .testTarget(name: "FileToolsTests", dependencies: ["FileTools"])
])
''')
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(package / "clang-cache"))
    result = subprocess.run([
        "swift", "test", "--package-path", str(package), "--disable-sandbox",
        "--cache-path", str(package / "cache")
    ], env=environment)
    raise SystemExit(result.returncode)
