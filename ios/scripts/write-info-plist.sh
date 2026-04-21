#!/usr/bin/env bash
# Write the canonical Info.plist for the BizarreCRM target.
# xcodegen 2.45.x silently drops our `info.properties:` block for reasons we
# don't fully understand, and Xcode's capability editor occasionally clobbers
# the file — both failure modes lead to silent regressions (letterbox, missing
# permissions, broken URL scheme). Taking full control via this script removes
# the ambiguity: the file is a build artifact, regenerated before every
# xcodegen run by scripts/gen.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLIST="${IOS_DIR}/App/Resources/Info.plist"

mkdir -p "$(dirname "${PLIST}")"

cat > "${PLIST}" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Bizarre CRM</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.0</string>

    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>

    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <true/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneConfigurationName</key>
                    <string>Default Configuration</string>
                    <key>UISceneClassName</key>
                    <string>UIWindowScene</string>
                    <key>UISceneDelegateClassName</key>
                    <string></string>
                </dict>
            </array>
        </dict>
    </dict>

    <key>UIBackgroundModes</key>
    <array>
        <string>remote-notification</string>
        <string>processing</string>
        <string>fetch</string>
    </array>

    <key>UILaunchScreen</key>
    <dict>
        <key>UIImageRespectsSafeAreaInsets</key>
        <true/>
        <key>UIColorName</key>
        <string>SurfaceBase</string>
    </dict>

    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>

    <key>NSCameraUsageDescription</key>
    <string>Scan barcodes and take photos of devices under repair.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Attach existing photos to repair tickets.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Save ticket photos to your library.</string>
    <key>NSFaceIDUsageDescription</key>
    <string>Authenticate to unlock Bizarre CRM.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Connect to Bluetooth receipt printers and card readers.</string>
    <key>NSContactsUsageDescription</key>
    <string>Import customer phone numbers from Contacts.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Record voice memos to attach to tickets and messages.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Verify you are at the shop when clocking in.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Discover your shop server and payment terminal on the local network.</string>
    <!-- §10.9 Calendar integration — required iOS 17+ -->
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Add appointments directly to your iOS Calendar.</string>

    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>

    <key>NSUserActivityTypes</key>
    <array>
        <!-- §25 Handoff / Continuity — HandoffActivityType constants -->
        <string>com.bizarrecrm.ticket.view</string>
        <string>com.bizarrecrm.ticket.create</string>
        <string>com.bizarrecrm.customer.view</string>
        <string>com.bizarrecrm.invoice.view</string>
        <string>com.bizarrecrm.dashboard</string>
    </array>

    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.bizarrecrm</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>bizarrecrm</string>
            </array>
        </dict>
    </array>

    <key>UIAppFonts</key>
    <array>
        <string>Inter-Regular.ttf</string>
        <string>Inter-Medium.ttf</string>
        <string>Inter-SemiBold.ttf</string>
        <string>Inter-Bold.ttf</string>
        <string>BarlowCondensed-SemiBold.ttf</string>
        <string>BarlowCondensed-Bold.ttf</string>
        <string>JetBrainsMono-Regular.ttf</string>
        <string>JetBrainsMono-Medium.ttf</string>
    </array>

    <!-- §24 Live Activities — required for ActivityKit -->
    <key>NSSupportsLiveActivities</key>
    <true/>
    <!-- §24 Live Activities push-to-start (iOS 17.2+) -->
    <key>NSSupportsLiveActivitiesFrequentUpdates</key>
    <true/>

    <key>BZ_API_BASE_URL</key>
    <string>$(BZ_API_BASE_URL)</string>
    <key>BZ_SPKI_PINS</key>
    <string>$(BZ_SPKI_PINS)</string>
</dict>
</plist>
PLIST_EOF

echo "✓ wrote ${PLIST}"
