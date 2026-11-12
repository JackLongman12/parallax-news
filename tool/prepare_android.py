#!/usr/bin/env python3
"""Patch the `flutter create`-generated Android project with what this app needs.

Run from the repo root after:
  flutter create --platforms=android --org com.parallaxnews --project-name parallax_news .
  flutter pub get
Idempotent: safe to run more than once.
"""
import json
import pathlib
import re
import sys
from urllib.parse import urlparse, unquote

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
RES_XML = ROOT / "android/app/src/main/res/xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.REQUEST_INSTALL_PACKAGES",
]

PROVIDER = """        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/filepaths" />
        </provider>
"""

FILEPATHS = """<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-files-path name="external_files" path="." />
    <external-path name="external_download" path="Download" />
    <files-path name="files" path="." />
    <cache-path name="cache" path="." />
</paths>
"""

QUERIES = """        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
"""


def plugin_declares_provider() -> bool:
    """True if the resolved ota_update plugin already ships its own FileProvider."""
    cfg = ROOT / ".dart_tool/package_config.json"
    if not cfg.exists():
        return False
    for pkg in json.loads(cfg.read_text(encoding="utf-8"))["packages"]:
        if pkg["name"] != "ota_update":
            continue
        uri = pkg["rootUri"]
        path = pathlib.Path(unquote(urlparse(uri).path)) if uri.startswith("file:") else (cfg.parent / uri)
        if sys.platform == "win32" and str(path).startswith("\\"):
            path = pathlib.Path(str(path).lstrip("\\"))
        m = path / "android/src/main/AndroidManifest.xml"
        if m.exists() and "<provider" in m.read_text(encoding="utf-8"):
            print("ota_update ships its own provider; not adding one")
            return True
    return False


def main() -> None:
    if not MANIFEST.exists():
        sys.exit(f"{MANIFEST} not found - run flutter create first")
    text = MANIFEST.read_text(encoding="utf-8")

    for perm in PERMISSIONS:
        tag = f'<uses-permission android:name="{perm}" />'
        if perm not in text:
            text = text.replace("<application", f"{tag}\n    <application", 1)

    text = re.sub(r'android:label="[^"]*"', 'android:label="Parallax News"', text, count=1)

    # Never allow plain-HTTP traffic; all providers are HTTPS.
    if "usesCleartextTraffic" not in text:
        text = text.replace("<application", '<application\n        android:usesCleartextTraffic="false"', 1)
    # Don't let adb backups copy reading history / learned profile off the phone.
    if "android:allowBackup" not in text:
        text = text.replace("<application", '<application\n        android:allowBackup="false"', 1)

    if "OtaUpdateFileProvider" not in text and not plugin_declares_provider():
        text = text.replace("</application>", PROVIDER + "    </application>", 1)
        RES_XML.mkdir(parents=True, exist_ok=True)
        (RES_XML / "filepaths.xml").write_text(FILEPATHS, encoding="utf-8")

    if 'android:scheme="https"' not in text:
        if "<queries>" in text:
            text = text.replace("<queries>", "<queries>\n" + QUERIES, 1)
        else:
            text = text.replace("</manifest>", "    <queries>\n" + QUERIES + "    </queries>\n</manifest>", 1)

    MANIFEST.write_text(text, encoding="utf-8")
    print("AndroidManifest.xml patched")
    patch_gradle()


def patch_root_gradle() -> None:
    """Android Lint crashes analysing a plugin (url_launcher_android) - a lint bug,
    not ours. Dart code is gated by `flutter analyze` + tests instead."""
    kts = ROOT / "android/build.gradle.kts"
    groovy = ROOT / "android/build.gradle"
    gradle = kts if kts.exists() else groovy
    text = gradle.read_text(encoding="utf-8")
    if "lintVital" in text:
        return
    if gradle == kts:
        text += '\nsubprojects {\n    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }\n}\n'
    else:
        text += "\nsubprojects {\n    tasks.matching { it.name.startsWith('lintVital') }.configureEach { enabled = false }\n}\n"
    gradle.write_text(text, encoding="utf-8")
    print(f"root {gradle.name} patched (lintVital off)")


def patch_gradle() -> None:
    """ota_update needs core library desugaring."""
    patch_root_gradle()
    kts = ROOT / "android/app/build.gradle.kts"
    groovy = ROOT / "android/app/build.gradle"
    gradle = kts if kts.exists() else groovy
    text = gradle.read_text(encoding="utf-8")
    if "CoreLibraryDesugaring" in text or "coreLibraryDesugaring" in text:
        return
    if gradle == kts:
        text = text.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
        text += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        text = text.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
        text += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if "esugaringEnabled" not in text:
        sys.exit("could not find compileOptions block in " + str(gradle))
    gradle.write_text(text, encoding="utf-8")
    print(f"{gradle.name} patched (desugaring)")


if __name__ == "__main__":
    main()
