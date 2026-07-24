#!/usr/bin/env python3
"""Apply native Android requirements for Vibe.

Run after `flutter create --platforms=android ...` when this repository has no
checked-in Android platform directory. The script is idempotent and configures:
- FragmentActivity for local_auth;
- microphone and biometric permissions;
- FLAG_SECURE screen protection through a Flutter MethodChannel;
- the custom `vibe://` deep-link scheme.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def replace(path: Path, old: str, new: str) -> bool:
    source = path.read_text(encoding="utf-8")
    updated = source.replace(old, new)
    if updated == source:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def configure_kotlin_activity(path: Path) -> bool:
    source = path.read_text(encoding="utf-8")
    package_match = re.search(r"^package\s+([\w.]+)\s*$", source, re.MULTILINE)
    if package_match is None:
        raise RuntimeError(f"Cannot determine package in {path}")
    package_name = package_match.group(1)
    expected = f'''package {package_name}

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vibe/screen_protection",
        ).setMethodCallHandler {{ call, result ->
            if (call.method != "setProtectedContent") {{
                result.notImplemented()
                return@setMethodCallHandler
            }}
            val enabled = call.argument<Boolean>("enabled") ?: false
            runOnUiThread {{
                if (enabled) {{
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }} else {{
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }}
                result.success(true)
            }}
        }}
    }}
}}
'''
    if source == expected:
        return False
    path.write_text(expected, encoding="utf-8")
    return True


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    android = root / "android"
    if not android.is_dir():
        print("android/ is missing; generate the platform template first", file=sys.stderr)
        return 2

    changed: list[str] = []
    main_source = android / "app" / "src" / "main"
    kotlin_activities = list(main_source.glob("**/MainActivity.kt"))
    java_activities = list(main_source.glob("**/MainActivity.java"))
    if not kotlin_activities and not java_activities:
        print("MainActivity.kt/.java was not found", file=sys.stderr)
        return 3

    for path in kotlin_activities:
        if configure_kotlin_activity(path):
            changed.append(str(path.relative_to(root)))

    for path in java_activities:
        did_change = replace(
            path,
            "io.flutter.embedding.android.FlutterActivity",
            "io.flutter.embedding.android.FlutterFragmentActivity",
        )
        did_change |= replace(path, "extends FlutterActivity", "extends FlutterFragmentActivity")
        if did_change:
            changed.append(str(path.relative_to(root)))
        print(
            "Warning: Java MainActivity detected; FLAG_SECURE MethodChannel requires manual wiring.",
            file=sys.stderr,
        )

    manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
    source = manifest.read_text(encoding="utf-8")
    lines = []
    if "android.permission.USE_BIOMETRIC" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.USE_BIOMETRIC\" />"
        )
    if "android.permission.RECORD_AUDIO" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />"
        )
    if lines:
        marker = source.find(">") + 1
        source = source[:marker] + "\n" + "\n".join(lines) + source[marker:]

    if 'android:scheme="vibe"' not in source:
        activity_end = source.find("</activity>")
        if activity_end < 0:
            raise RuntimeError("AndroidManifest.xml has no activity element")
        deep_link = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="vibe" />
            </intent-filter>
'''
        source = source[:activity_end] + deep_link + source[activity_end:]

    if source != manifest.read_text(encoding="utf-8"):
        manifest.write_text(source, encoding="utf-8")
        changed.append(str(manifest.relative_to(root)))

    style_parents = (
        "@android:style/Theme.Light.NoTitleBar",
        "@android:style/Theme.Black.NoTitleBar",
    )
    for path in (main_source / "res").glob("values*/styles.xml"):
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
