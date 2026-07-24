#!/usr/bin/env python3
"""Idempotently configure generated Flutter Android files for Firebase FCM.

Run after `flutter create --platforms=android ...` and before Gradle build.
This script never creates google-services.json; CI must materialize that file
from an encrypted secret and local builds receive it from Firebase Console.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def write_if_changed(path: Path, content: str) -> bool:
    current = path.read_text(encoding="utf-8")
    if current == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    android = root / "android"
    if not android.is_dir():
        print("android/ is missing; generate the platform template first", file=sys.stderr)
        return 2

    changed: list[str] = []

    settings = android / "settings.gradle.kts"
    settings_source = settings.read_text(encoding="utf-8")
    if 'id("com.google.gms.google-services")' not in settings_source:
        needle = '    id("org.jetbrains.kotlin.android") version "2.3.20" apply false'
        if needle in settings_source:
            settings_source = settings_source.replace(
                needle,
                needle + '\n    id("com.google.gms.google-services") version "4.5.0" apply false',
            )
        else:
            plugins_end = settings_source.find('\n}\n\ninclude(":app")')
            if plugins_end < 0:
                raise RuntimeError("Cannot locate plugins block in settings.gradle.kts")
            settings_source = (
                settings_source[:plugins_end]
                + '\n    id("com.google.gms.google-services") version "4.5.0" apply false'
                + settings_source[plugins_end:]
            )
    if write_if_changed(settings, settings_source):
        changed.append(str(settings.relative_to(root)))

    app_gradle = android / "app" / "build.gradle.kts"
    app_source = app_gradle.read_text(encoding="utf-8")
    if 'id("com.google.gms.google-services")' not in app_source:
        app_source = app_source.replace(
            '    id("com.android.application")',
            '    id("com.android.application")\n    id("com.google.gms.google-services")',
            1,
        )
    if 'isCoreLibraryDesugaringEnabled = true' not in app_source:
        app_source = app_source.replace(
            '    compileOptions {',
            '    compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
            1,
        )
    if 'com.google.firebase:firebase-bom' not in app_source:
        dependencies = '''

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
}
'''
        marker = '\nkotlin {'
        if marker not in app_source:
            raise RuntimeError("Cannot locate kotlin block in app/build.gradle.kts")
        app_source = app_source.replace(marker, dependencies + marker, 1)
    if write_if_changed(app_gradle, app_source):
        changed.append(str(app_gradle.relative_to(root)))

    manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
    manifest_source = manifest.read_text(encoding="utf-8")
    root_permissions = [
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.SCHEDULE_EXACT_ALARM',
        'android.permission.USE_EXACT_ALARM',
        'android.permission.USE_FULL_SCREEN_INTENT',
    ]
    permissions = [
        f'    <uses-permission android:name="{permission}" />'
        for permission in root_permissions
        if permission not in manifest_source
    ]
    if permissions:
        first_tag_end = manifest_source.find('>') + 1
        manifest_source = (
            manifest_source[:first_tag_end]
            + '\n'
            + '\n'.join(permissions)
            + manifest_source[first_tag_end:]
        )
    firebase_metadata = '''
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="vibe_messages" />
'''
    if 'com.google.firebase.messaging.default_notification_channel_id' not in manifest_source:
        application_end = manifest_source.find('</application>')
        if application_end < 0:
            raise RuntimeError("Cannot locate application block in AndroidManifest.xml")
        manifest_source = (
            manifest_source[:application_end]
            + firebase_metadata
            + manifest_source[application_end:]
        )
    if write_if_changed(manifest, manifest_source):
        changed.append(str(manifest.relative_to(root)))

    print("Firebase Android configuration ready.")
    print("Updated: " + (", ".join(changed) if changed else "none"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
