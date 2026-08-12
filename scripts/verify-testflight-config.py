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
KEYCHAIN_ACCESS_GROUP = "$(AppIdentifierPrefix)run.kan.koyomi.shared"
SIGNED_KEYCHAIN_ACCESS_GROUP = f"{TEAM_ID}.run.kan.koyomi.shared"
SUPPORTED_INTERFACE_ORIENTATIONS = ["UIInterfaceOrientationPortrait"]
EXPECTED_BUILD_NUMBER = "4"
EXPECTED_WIDGET_FAMILIES = (
    ".supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])"
)


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
    require_yaml_setting(project, "MARKETING_VERSION", "2.0.0")
    require_yaml_setting(project, "CURRENT_PROJECT_VERSION", EXPECTED_BUILD_NUMBER)
    require_yaml_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", APP_ID)
    require_yaml_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", WIDGET_ID)
    assert project.count('TARGETED_DEVICE_FAMILY: "1"') == 4, (
        "every generated target must be iPhone-only"
    )

    assert project.count("path: Resources/PrivacyInfo.xcprivacy") == 2, (
        "PrivacyInfo.xcprivacy must be embedded in the app and widget"
    )
    assert "archive:\n      config: Release" in project, "Koyomi scheme must archive Release"

    expected_resources = (
        "- path: Shared\n"
        "      - path: Resources/PrivacyInfo.xcprivacy\n"
        "        buildPhase: resources\n"
        "        type: file"
    )
    assert project.count(expected_resources) == 2, (
        "privacy manifest must be an explicit resources build-phase source in app and widget targets"
    )

    app_info = load_plist("Koyomi/Info.plist")
    assert app_info.get("ITSAppUsesNonExemptEncryption") is False, (
        "Koyomi/Info.plist must declare no non-exempt encryption"
    )
    assert app_info.get("UISupportedInterfaceOrientations") == SUPPORTED_INTERFACE_ORIENTATIONS, (
        "Koyomi/Info.plist must declare the supported iPhone orientation"
    )

    app_entitlements = load_plist("Koyomi/Koyomi.entitlements")
    widget_entitlements = load_plist("KoyomiWidget/KoyomiWidget.entitlements")
    expected_groups = [KEYCHAIN_ACCESS_GROUP]
    assert app_entitlements.get("keychain-access-groups") == expected_groups
    assert widget_entitlements.get("keychain-access-groups") == expected_groups
    assert "com.apple.security.application-groups" not in app_entitlements
    assert "com.apple.security.application-groups" not in widget_entitlements
    assert project.count(KEYCHAIN_ACCESS_GROUP) == 2

    app_dependencies = (ROOT / "Koyomi/AppDependencies.swift").read_text(encoding="utf-8")
    shared_storage = (ROOT / "Shared/PinnedEvent.swift").read_text(encoding="utf-8")
    widget_source = (ROOT / "KoyomiWidget/KoyomiWidget.swift").read_text(encoding="utf-8")
    assert "pinStore: PinnedEventsStore(storage: KeychainPinnedEventsDataStorage())" in app_dependencies
    assert "account: KoyomiSharedStorage.legacyPinnedEventsKey" in app_dependencies
    assert "key: KoyomiSharedStorage.legacyPinnedEventsKey" in app_dependencies
    assert 'pinnedEventSnapshotsKey = "pinned-event-snapshots-v2"' in shared_storage
    assert 'legacyPinnedEventsKey = "pinned-events-v1"' in shared_storage
    assert "PinnedEventsStore(storage: KeychainPinnedEventsDataStorage())" in widget_source
    assert EXPECTED_WIDGET_FAMILIES in widget_source, (
        "the widget must advertise Small, Medium, Large, and accessory rectangular families"
    )

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

    workflow = (ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8")
    assert '--time "9:41"' in workflow, "simctl must use its accepted screenshot time"
    assert "STATUS_TIME=" not in workflow, "midnight HH:mm values are rejected by simctl"
    assert workflow.count('".github/workflows/testflight.yml"') == 2
    assert "workflow-lint:" in workflow
    assert "rhysd/actionlint@sha256:" in workflow
    assert "Verify embedded privacy manifests" in workflow
    assert "KoyomiWidget.appex" in workflow
    assert '"$WIDGET_PATH/PrivacyInfo.xcprivacy"' in workflow
    assert workflow.count("cmp -s Resources/PrivacyInfo.xcprivacy") == 2

    deploy_path = ROOT / ".github/workflows/testflight.yml"
    assert deploy_path.is_file(), "reusable TestFlight workflow is missing"
    deploy = deploy_path.read_text(encoding="utf-8")
    for required in (
        "workflow_call:",
        "source_ref:",
        "required: true",
        "persist-credentials: false",
        "uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
        "uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
        "CI_KEYCHAIN_PASSWORD:",
        "ASC_ISSUER_ID:",
        "ASC_KEY_ID:",
        "ASC_PRIVATE_KEY:",
        "fromJSON(inputs.runner_labels)",
        "repository: kandotrun/koyomi-ios",
        "xcodebuild archive",
        "-exportArchive",
        "-allowProvisioningUpdates",
        "-authenticationKeyPath",
        "ExportOptions.plist",
        "mktemp -d \"$RUNNER_TEMP/koyomi-signing.XXXXXX\"",
        "OTHER_CODE_SIGN_FLAGS=\"--keychain $CI_KEYCHAIN_PATH\"",
        "security delete-keychain \"$CI_KEYCHAIN_PATH\"",
        "ORIGINAL_DEFAULT_KEYCHAIN",
        "ORIGINAL_KEYCHAIN_LIST_PATH",
        "cleanup_status=0",
        "Remove temporary signing keychain",
        "command -v xcodegen",
        "DEVELOPER_DIR=",
        "XCODE_VERSION_OUTPUT=$(xcodebuild -version)",
        "BEGIN PRIVATE KEY",
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-",
        "Print :keychain-access-groups:0",
        "Print :keychain-access-groups:1",
        "Signed archive Keychain sharing: PASS",
        "rm -f \"$API_KEY_PATH\"",
    ):
        assert required in deploy, f"TestFlight workflow missing: {required}"
    assert deploy.count(SIGNED_KEYCHAIN_ACCESS_GROUP) >= 2, (
        "TestFlight archive must verify the shared Keychain group for app and widget"
    )
    assert "group.run.kan.koyomi" not in deploy, (
        "TestFlight workflow must not require the retired App Group"
    )
    for forbidden in (
        "workflow_dispatch:",
        "push:",
        "pull_request:",
        "default: main",
        "brew install",
        "sudo xcode-select",
        "rm -rf",
        "LOGIN_KEYCHAIN=",
        "xcodebuild -version | grep -Eq",
        "uses: actions/checkout@v",
        "uses: actions/upload-artifact@v",
        'security lock-keychain "$KEYCHAIN_PATH"',
    ):
        assert forbidden not in deploy, f"public deploy workflow must not expose {forbidden}"

    print("TestFlight distribution contract: PASS")


if __name__ == "__main__":
    main()
