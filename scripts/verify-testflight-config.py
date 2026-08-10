#!/usr/bin/env python3
"""Verify Koyomi's checked-in TestFlight distribution contract."""

from __future__ import annotations

import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEAM_ID = "UGNVGWZMAU"
APP_ID = "run.kan.koyomi"
WIDGET_ID = "run.kan.koyomi.widget"
APP_GROUP = "group.run.kan.koyomi"


def load_plist(relative_path: str) -> dict:
    with (ROOT / relative_path).open("rb") as handle:
        return plistlib.load(handle)


def require_yaml_setting(project: str, key: str, expected: str) -> None:
    pattern = rf"(?m)^\s+{re.escape(key)}:\s*[\"']?{re.escape(expected)}[\"']?\s*$"
    assert re.search(pattern, project), f"{key} must be {expected!r}"


def main() -> None:
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    require_yaml_setting(project, "DEVELOPMENT_TEAM", TEAM_ID)
    require_yaml_setting(project, "CODE_SIGN_STYLE", "Automatic")
    require_yaml_setting(project, "MARKETING_VERSION", "1.0.0")
    require_yaml_setting(project, "CURRENT_PROJECT_VERSION", "1")
    require_yaml_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", APP_ID)
    require_yaml_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", WIDGET_ID)

    assert project.count("path: Resources/PrivacyInfo.xcprivacy") == 2, (
        "PrivacyInfo.xcprivacy must be embedded in the app and widget"
    )
    assert "archive:\n      config: Release" in project, "Koyomi scheme must archive Release"

    app_info = load_plist("Koyomi/Info.plist")
    assert app_info.get("ITSAppUsesNonExemptEncryption") is False, (
        "Koyomi/Info.plist must declare no non-exempt encryption"
    )

    app_entitlements = load_plist("Koyomi/Koyomi.entitlements")
    widget_entitlements = load_plist("KoyomiWidget/KoyomiWidget.entitlements")
    expected_groups = [APP_GROUP]
    assert app_entitlements.get("com.apple.security.application-groups") == expected_groups
    assert widget_entitlements.get("com.apple.security.application-groups") == expected_groups

    privacy = load_plist("Resources/PrivacyInfo.xcprivacy")
    assert privacy.get("NSPrivacyTracking") is False
    assert privacy.get("NSPrivacyCollectedDataTypes") == []
    accessed = privacy.get("NSPrivacyAccessedAPITypes")
    assert accessed == [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": ["1C8F.1"],
        }
    ]

    export = load_plist("ExportOptions.plist")
    assert export.get("destination") == "upload"
    assert export.get("method") == "app-store-connect"
    assert export.get("signingStyle") == "automatic"
    assert export.get("teamID") == TEAM_ID
    assert export.get("manageAppVersionAndBuildNumber") is True
    assert export.get("uploadSymbols") is True

    print("TestFlight distribution contract: PASS")


if __name__ == "__main__":
    main()
