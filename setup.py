#!/usr/bin/env python3
"""
EntiDB Sync - Development Setup Script

Cross-platform setup script that checks prerequisites and installs
dependencies for all packages in the monorepo.

Usage:
    python setup.py
"""

import os
import platform
import re
import subprocess
import sys
from pathlib import Path


def run_command(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    """Run a command and return exit code, stdout, stderr."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr
    except FileNotFoundError:
        return 1, "", f"Command not found: {cmd[0]}"


def check_dart_version() -> str | None:
    """Check if Dart SDK is installed and return version."""
    code, stdout, stderr = run_command(["dart", "--version"])
    if code != 0:
        return None
    
    # Parse version from output like "Dart SDK version: 3.10.4 (stable) ..."
    output = stdout + stderr
    match = re.search(r"Dart SDK version:\s*(\d+\.\d+\.\d+)", output)
    if match:
        return match.group(1)
    return None


def version_tuple(version: str) -> tuple[int, ...]:
    """Convert version string to tuple for comparison."""
    return tuple(int(x) for x in version.split("."))


def install_package_deps(package_path: Path) -> bool:
    """Run dart pub get for a package."""
    code, stdout, stderr = run_command(["dart", "pub", "get"], cwd=package_path)
    if code != 0:
        print(f"  ❌ Failed: {stderr}")
        return False
    return True


def main() -> int:
    """Main setup function."""
    print("EntiDB Sync - Development Setup")
    print("================================")
    print(f"Platform: {platform.system()} ({platform.machine()})")
    print()

    # Get repository root (directory containing this script)
    repo_root = Path(__file__).parent.resolve()
    os.chdir(repo_root)

    # Check Dart SDK
    print("Checking Dart SDK version...")
    dart_version = check_dart_version()
    
    if dart_version is None:
        print("❌ Dart SDK not found. Please install from https://dart.dev/get-dart")
        return 1
    
    print(f"✓ Found Dart SDK {dart_version}")

    # Check version >= 3.10.1
    min_version = (3, 10, 1)
    if version_tuple(dart_version) < min_version:
        print(f"⚠️  Warning: Dart SDK 3.10.1+ is required (you have {dart_version})")
        print("   Upgrade with: dart channel stable && dart upgrade")
        return 1

    print()
    print("Installing dependencies...")
    print()

    # Package list in dependency order
    packages = [
        "entidb_sync_protocol",
        "entidb_sync_client", 
        "entidb_sync_server",
    ]

    success = True
    for package in packages:
        package_path = repo_root / "packages" / package
        if not package_path.exists():
            print(f"📦 {package}")
            print(f"  ❌ Package directory not found: {package_path}")
            success = False
            continue

        print(f"📦 {package}")
        if install_package_deps(package_path):
            print("  ✓ Dependencies installed")
        else:
            success = False

    print()
    
    if success:
        print("✅ Setup complete!")
        print()
        print("Next steps:")
        print("  • Review documentation: doc/architecture.md")
        print("  • Run tests: dart test packages/<package>/test")
        print("  • Start development: see CONTRIBUTING.md")
        return 0
    else:
        print("❌ Setup completed with errors")
        return 1


if __name__ == "__main__":
    sys.exit(main())
