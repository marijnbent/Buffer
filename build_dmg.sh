#!/bin/bash
set -e

APP_NAME="Buffer"
BUNDLE_ID="com.samirpatil.Buffer"
DEPLOY_TARGET="13.0"

echo "🧹 Cleaning up old build..."
rm -rf build
mkdir -p build/${APP_NAME}.app/Contents/MacOS
mkdir -p build/${APP_NAME}.app/Contents/Resources

echo "🔨 Compiling Swift files..."
swiftc \
  -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -target $(uname -m)-apple-macosx${DEPLOY_TARGET} \
  -parse-as-library \
  -framework Cocoa \
  -framework SwiftUI \
  -framework Carbon \
  *.swift Models/*.swift Services/*.swift Views/*.swift \
  -o build/${APP_NAME}.app/Contents/MacOS/${APP_NAME}

echo "📋 Creating resolved Info.plist..."
cat > build/${APP_NAME}.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Buffer</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>LSApplicationCategoryType</key>
	<string></string>
	<key>CFBundleIdentifier</key>
	<string>com.samirpatil.Buffer</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Buffer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2024. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "🎨 Compiling Assets..."
xcrun actool Assets.xcassets \
  --compile build/${APP_NAME}.app/Contents/Resources \
  --platform macosx \
  --minimum-deployment-target ${DEPLOY_TARGET} \
  --app-icon AppIcon \
  --output-partial-info-plist build/partial.plist 2>/dev/null

echo "📦 Writing PkgInfo..."
echo "APPL????" > build/${APP_NAME}.app/Contents/PkgInfo

echo "🔏 Code signing..."
codesign --force --deep --sign - --entitlements Buffer.entitlements build/${APP_NAME}.app

echo "🧼 Removing quarantine attribute..."
xattr -cr build/${APP_NAME}.app

echo "🔗 Adding Applications shortcut to DMG folder..."
ln -s /Applications build/Applications

echo "💿 Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder build \
  -ov \
  -format UDZO \
  Buffer_Release.dmg

echo "🧼 Removing quarantine from DMG..."
xattr -cr Buffer_Release.dmg

echo ""
echo "✅ Done! DMG is located at: Buffer_Release.dmg"
echo "   If macOS still complains, run:  xattr -cr /path/to/Buffer.app"
