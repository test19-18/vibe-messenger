#!/usr/bin/env python3
"""Patch file_picker 11.x for AGP 9 legacy-Kotlin mode.

file_picker 11.0.2 skips its Kotlin plugin whenever it detects AGP 9, while
Flutter's current Android template can still run with android.builtInKotlin=false
because other plugins have not all migrated. In that compatibility mode the
plugin's Kotlin sources would otherwise not compile, leaving the generated
registrant without FilePickerPlugin.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    package_config = root / ".dart_tool" / "package_config.json"
    if not package_config.is_file():
        print("Run flutter pub get before this patch", file=sys.stderr)
        return 2

    config = json.loads(package_config.read_text(encoding="utf-8"))
    entry = next(
        (package for package in config["packages"] if package["name"] == "file_picker"),
        None,
    )
    if entry is None:
        print("file_picker is not in package_config.json", file=sys.stderr)
        return 3

    parsed = urlparse(entry["rootUri"])
    package_root = Path(unquote(parsed.path if parsed.scheme == "file" else entry["rootUri"]))
    build_file = package_root / "android" / "build.gradle"
    source = build_file.read_text(encoding="utf-8")

    conditional_plugin = """if (!isAgp9OrAbove) {
    apply plugin: 'org.jetbrains.kotlin.android'
}"""
    unconditional_plugin = "apply plugin: 'org.jetbrains.kotlin.android'"
    conditional_options = """    if (!isAgp9OrAbove) {
        kotlinOptions {
            jvmTarget = JavaVersion.VERSION_17.toString()
        }
    }"""
    unconditional_options = """    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }"""

    updated = source.replace(conditional_plugin, unconditional_plugin)
    updated = updated.replace(conditional_options, unconditional_options)
    if updated == source:
        if conditional_plugin not in source and unconditional_plugin in source:
            print("file_picker AGP 9 compatibility patch already applied")
            return 0
        print("file_picker build.gradle layout changed; refusing a blind patch", file=sys.stderr)
        return 4

    build_file.write_text(updated, encoding="utf-8")
    print(f"Patched {build_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
