#!/bin/bash
set -euo pipefail

# ==============================================================================
# Sutra Native DMG Packager
# Zero-Bloat, Dependency-Free Apple Disk Image Creator
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/bin/Sutra.app"
CLI_BINARY="$PROJECT_ROOT/bin/sutra"
DIST_DIR="$PROJECT_ROOT/dist"
OUTPUT_DMG="${1:-$DIST_DIR/Sutra-Installer.dmg}"

echo "🪡 Sutra Native DMG Packager"
echo "──────────────────────────────────────────────"

# 1. Ensure output directory exists
mkdir -p "$DIST_DIR"

# 2. Verify Prerequisites
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: App bundle not found at $APP_BUNDLE"
    exit 1
fi

if [ ! -f "$CLI_BINARY" ]; then
    echo "❌ Error: CLI binary not found at $CLI_BINARY"
    exit 1
fi

# 3. Ensure CLI and assets are bundled inside App Resources
echo "📦 Embedding CLI & assets into Sutra.app/Contents/Resources..."
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp -f "$CLI_BINARY" "$APP_BUNDLE/Contents/Resources/sutra"
chmod +x "$APP_BUNDLE/Contents/Resources/sutra"

if [ -f "$PROJECT_ROOT/assets/logo.png" ]; then
    cp -f "$PROJECT_ROOT/assets/logo.png" "$APP_BUNDLE/Contents/Resources/logo.png"
fi
if [ -f "$PROJECT_ROOT/assets/antigravity.png" ]; then
    cp -f "$PROJECT_ROOT/assets/antigravity.png" "$APP_BUNDLE/Contents/Resources/antigravity.png"
fi
if [ -f "$PROJECT_ROOT/docs/USER_GUIDE.html" ]; then
    echo "📄 Embedding USER_GUIDE.html into App Resources..."
    cp -f "$PROJECT_ROOT/docs/USER_GUIDE.html" "$APP_BUNDLE/Contents/Resources/USER_GUIDE.html"
fi

# 4. Ad-hoc Codesign
echo "🔐 Codesigning Sutra.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

# 5. Staging Folder
STAGING_DIR=$(mktemp -d /tmp/sutra-dmg-XXXXXX)
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "📁 Staging application, documentation & /Applications symlink..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/Sutra.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [ -f "$PROJECT_ROOT/docs/USER_GUIDE.html" ]; then
    echo "📖 Staging Sutra User Guide.html on DMG root volume..."
    cp -f "$PROJECT_ROOT/docs/USER_GUIDE.html" "$STAGING_DIR/Sutra User Guide.html"
fi

# 6. Generate DMG using macOS native hdiutil
echo "📀 Building compressed UDZO disk image..."
rm -f "$OUTPUT_DMG"
hdiutil create \
    -volname "Sutra" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG" > /dev/null

# 7. Verification & Metrics
DMG_SIZE=$(du -h "$OUTPUT_DMG" | awk '{print $1}')
echo "──────────────────────────────────────────────"
echo "✅ DMG Created Successfully!"
echo "📍 Location: $OUTPUT_DMG"
echo "⚖️  Size:     $DMG_SIZE (Zero-bloat native container)"
echo ""
echo "🚀 To test mounting:"
echo "   open \"$OUTPUT_DMG\""
echo "──────────────────────────────────────────────"
