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


def write_if_changed(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.write_text(content, encoding="utf-8")
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
    source = source.replace('android:label="vibe_messenger"', 'android:label="Вайб"')
    source = source.replace(
        'android:icon="@mipmap/ic_launcher">',
        'android:icon="@drawable/vibe_launcher_icon"\n        android:roundIcon="@drawable/vibe_launcher_icon">',
    )
    lines = []
    if "android.permission.INTERNET" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.INTERNET\" />"
        )
    if "android.permission.USE_BIOMETRIC" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.USE_BIOMETRIC\" />"
        )
    if "android.permission.RECORD_AUDIO" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />"
        )
    for permission in (
        "android.permission.CAMERA",
        "android.permission.BLUETOOTH_CONNECT",
        "android.permission.MODIFY_AUDIO_SETTINGS",
        "android.permission.BIND_TELECOM_CONNECTION_SERVICE",
        "android.permission.MANAGE_OWN_CALLS",
        "android.permission.READ_PHONE_STATE",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.SCHEDULE_EXACT_ALARM",
        "android.permission.USE_EXACT_ALARM",
        "android.permission.USE_FULL_SCREEN_INTENT",
    ):
        if permission not in source:
            lines.append(f"    <uses-permission android:name=\"{permission}\" />")
    if "android.permission.BLUETOOTH\" android:maxSdkVersion=\"30" not in source:
        lines.append(
            "    <uses-permission android:name=\"android.permission.BLUETOOTH\" android:maxSdkVersion=\"30\" />"
        )
    if lines:
        marker = source.find(">") + 1
        source = source[:marker] + "\n" + "\n".join(lines) + source[marker:]

    activity_end = source.find("</activity>")
    if activity_end < 0:
        raise RuntimeError("AndroidManifest.xml has no activity element")
    if 'android:scheme="vibe"' not in source:
        group_deep_link = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="vibe" />
            </intent-filter>
'''
        source = source[:activity_end] + group_deep_link + source[activity_end:]
        activity_end = source.find("</activity>")
    if 'android:scheme="ru.vibe.messenger"' not in source:
        auth_deep_link = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="ru.vibe.messenger"
                    android:host="auth"
                    android:pathPrefix="/callback" />
            </intent-filter>
'''
        source = source[:activity_end] + auth_deep_link + source[activity_end:]

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

    drawable_dir = main_source / "res" / "drawable"
    drawables = {
        "vibe_launcher_background.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="22dp" />
    <solid android:color="#17181D" />
</shape>
''',
        "vibe_launcher_foreground.xml": '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#3D7CFF"
        android:pathData="M12,2C6.48,2 2,6.03 2,11c0,2.24 0.91,4.29 2.42,5.86L3.2,21.7l5.07,-1.98C9.44,20.09 10.69,20.3 12,20.3c5.52,0 10,-4.03 10,-9.15C22,6.03 17.52,2 12,2z" />
    <path android:fillColor="@android:color/transparent"
        android:pathData="M6.8,8.2L6.8,15.2C6.8,16.3 8.1,16.7 8.7,15.7L11.1,10.6C11.5,9.7 12.6,9.7 13,10.6L14.6,13.6C15.1,14.5 16.3,14.4 16.7,13.5L18,10.2"
        android:strokeColor="#FFFFFF" android:strokeLineCap="round"
        android:strokeLineJoin="round" android:strokeWidth="1.7" />
</vector>
''',
        "vibe_launcher_icon.xml": '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@drawable/vibe_launcher_background" />
    <item android:bottom="12dp" android:left="12dp" android:right="12dp"
        android:top="12dp" android:drawable="@drawable/vibe_launcher_foreground" />
</layer-list>
''',
    }
    for name, content in drawables.items():
        path = drawable_dir / name
        if write_if_changed(path, content):
            changed.append(str(path.relative_to(root)))

    gradle_properties = android / "gradle.properties"
    gradle_source = gradle_properties.read_text(encoding="utf-8")
    gradle_source = re.sub(
        r"^org\.gradle\.jvmargs=.*$",
        "org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=192m -XX:+HeapDumpOnOutOfMemoryError",
        gradle_source,
        flags=re.MULTILINE,
    )
    gradle_source = gradle_source.replace(
        "android.builtInKotlin=true", "android.builtInKotlin=false"
    )
    required_gradle_lines = (
        "org.gradle.daemon=false",
        "org.gradle.workers.max=1",
        "kotlin.compiler.execution.strategy=in-process",
        "kotlin.daemon.jvmargs=-Xmx768m -XX:MaxMetaspaceSize=384m",
    )
    for line in required_gradle_lines:
        if line not in gradle_source:
            gradle_source += f"\n{line}"
    gradle_source = gradle_source.rstrip() + "\n"
    if gradle_source != gradle_properties.read_text(encoding="utf-8"):
        gradle_properties.write_text(gradle_source, encoding="utf-8")
        changed.append(str(gradle_properties.relative_to(root)))

    print("Android native configuration ready.")
    if changed:
        print("Updated: " + ", ".join(changed))
    else:
        print("No changes needed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
