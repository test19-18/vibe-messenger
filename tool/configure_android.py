#!/usr/bin/env python3
"""Apply the native Android requirements of local_auth and record.

Run after `flutter create --platforms=android ...` when this repository has no
checked-in Android platform directory.
"""

from __future__ import annotations

import sys
from pathlib import Path


def replace(path: Path, old: str, new: str) -> bool:
    source = path.read_text(encoding="utf-8")
    updated = source.replace(old, new)
    if updated == source:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    android = root / "android"
    if not android.is_dir():
        print("android/ is missing; generate the platform template first", file=sys.stderr)
        return 2

    changed: list[str] = []
    activity_files = list(
        (android / "app" / "src" / "main").glob("**/MainActivity.kt")
    ) + list((android / "app" / "src" / "main").glob("**/MainActivity.java"))
    if not activity_files:
        print("MainActivity.kt/.java was not found", file=sys.stderr)
        return 3

    for path in activity_files:
        did_change = replace(
            path,
            "io.flutter.embedding.android.FlutterActivity",
            "io.flutter.embedding.android.FlutterFragmentActivity",
        )
        did_change |= replace(path, "FlutterActivity()", "FlutterFragmentActivity()")
        did_change |= replace(path, "extends FlutterActivity", "extends FlutterFragmentActivity")
        if did_change:
            changed.append(str(path.relative_to(root)))

    manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
    source = manifest.read_text(encoding="utf-8")
    missing = (
        "android.permission.USE_BIOMETRIC" not in source
        or "android.permission.RECORD_AUDIO" not in source
    )
    if missing:
        lines = []
        if "android.permission.USE_BIOMETRIC" not in source:
            lines.append(
                "    <uses-permission android:name=\"android.permission.USE_BIOMETRIC\" />"
            )
        if "android.permission.RECORD_AUDIO" not in source:
            lines.append(
                "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />"
            )
        marker = source.find(">") + 1
        source = source[:marker] + "\n" + "\n".join(lines) + source[marker:]
        manifest.write_text(source, encoding="utf-8")
        changed.append(str(manifest.relative_to(root)))

    style_parents = (
        "@android:style/Theme.Light.NoTitleBar",
        "@android:style/Theme.Black.NoTitleBar",
    )
    for path in (android / "app" / "src" / "main" / "res").glob(
        "values*/styles.xml"
    ):
        did_change = False
        for parent in style_parents:
            did_change |= replace(
                path,
                f'parent="{parent}"',
                'parent="Theme.AppCompat.DayNight.NoActionBar"',
            )
        if did_change:
            changed.append(str(path.relative_to(root)))

    print("Android native configuration ready.")
    if changed:
        print("Updated: " + ", ".join(changed))
    else:
        print("No changes needed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
