#!/bin/zsh

# Script to generate macOS App Icon assets from a 1024x1024 icon.png
# Usage: ./generate_icons.sh [path_to_icon.png]
# If no argument is provided, uses assets/design/icon-clean.png

set -e  # Exit on any error

# Default icon path
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="${1:-$ROOT_DIR/assets/design/icon-clean.png}"

# Check if icon exists
if [[ ! -f "$ICON_PATH" ]]; then
    echo "Error: Icon file '$ICON_PATH' not found!"
    exit 1
fi

# Check if icon is 1024x1024
ICON_INFO=$(sips -g pixelWidth -g pixelHeight "$ICON_PATH" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}')
WIDTH=$(echo "$ICON_INFO" | head -1)
HEIGHT=$(echo "$ICON_INFO" | tail -1)

if [[ "$WIDTH" -ne 1024 || "$HEIGHT" -ne 1024 ]]; then
    echo "Warning: Icon is ${WIDTH}x${HEIGHT}, expected 1024x1024. Continuing anyway..."
fi

# Create output directory if it doesn't exist
OUTPUT_DIR="$ROOT_DIR/Sources/Cliptate/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUTPUT_DIR"

echo "Generating macOS App Icon assets from $ICON_PATH..."

# Generate icons
# 16x16 @1x
sips -z 16 16 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-16.png"

# 16x16 @2x (32x32)
sips -z 32 32 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-16@2x.png"

# 32x32 @1x
sips -z 32 32 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-32.png"

# 32x32 @2x (64x64)
sips -z 64 64 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-32@2x.png"

# 128x128 @1x
sips -z 128 128 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-128.png"

# 128x128 @2x (256x256)
sips -z 256 256 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-128@2x.png"

# 256x256 @1x
sips -z 256 256 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-256.png"

# 256x256 @2x (512x512)
sips -z 512 512 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-256@2x.png"

# 512x512 @1x
sips -z 512 512 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-512.png"

# 512x512 @2x (1024x1024) - must be exactly 1024x1024
sips -z 1024 1024 "$ICON_PATH" --out "$OUTPUT_DIR/app-icon-512@2x.png"

echo "All icon assets generated successfully in $OUTPUT_DIR/"
echo "Don't forget to update Contents.json if needed."
