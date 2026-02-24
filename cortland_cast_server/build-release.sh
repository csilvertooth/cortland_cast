#!/bin/bash

# Cortland Cast Server - Release Build Script
# Builds the Swift project and creates an app bundle in the current directory

set -e

echo "Building Cortland Cast Server (Swift)..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if swift is available
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift compiler not found. Please install Xcode and command line tools.${NC}"
    echo -e "${YELLOW}Run: xcode-select --install${NC}"
    exit 1
fi

echo -e "${BLUE}Cleaning previous build...${NC}"
make clean

echo -e "${BLUE}Building optimized release...${NC}"
if ! swift build --product CortlandCastServer --configuration release; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${BLUE}Creating app bundle...${NC}"

# Create app bundle structure
mkdir -p "Releases/Cortland Cast Server.app/Contents/MacOS"
mkdir -p "Releases/Cortland Cast Server.app/Contents/Resources"

# Copy executable
echo -e "${BLUE}Copying executable...${NC}"
cp ".build/arm64-apple-macosx/release/CortlandCastServer" "Releases/Cortland Cast Server.app/Contents/MacOS/CortlandCastServer"
chmod +x "Releases/Cortland Cast Server.app/Contents/MacOS/CortlandCastServer"

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp Info.plist "Releases/Cortland Cast Server.app/Contents/"
    echo -e "${BLUE}Copied Info.plist${NC}"
fi

# Copy icon if it exists
if [ -f "icon.icns" ]; then
    cp icon.icns "Releases/Cortland Cast Server.app/Contents/Resources/"
    echo -e "${BLUE}Copied icon.icns${NC}"
elif [ -f "cortland_cast_server_image.png" ]; then
    if command -v sips >/dev/null 2>&1; then
        echo -e "${YELLOW}Converting PNG to ICNS icon...${NC}"
        mkdir -p icon.iconset
        sips -z 16 16 cortland_cast_server_image.png --out icon.iconset/icon_16x16.png >/dev/null 2>&1
        sips -z 32 32 cortland_cast_server_image.png --out icon.iconset/icon_16x16@2x.png >/dev/null 2>&1
        sips -z 32 32 cortland_cast_server_image.png --out icon.iconset/icon_32x32.png >/dev/null 2>&1
        sips -z 64 64 cortland_cast_server_image.png --out icon.iconset/icon_32x32@2x.png >/dev/null 2>&1
        sips -z 128 128 cortland_cast_server_image.png --out icon.iconset/icon_128x128.png >/dev/null 2>&1
        sips -z 256 256 cortland_cast_server_image.png --out icon.iconset/icon_128x128@2x.png >/dev/null 2>&1
        sips -z 512 512 cortland_cast_server_image.png --out icon.iconset/icon_512x512.png >/dev/null 2>&1
        iconutil -c icns icon.iconset -o icon.icns >/dev/null 2>&1
        cp icon.icns "Releases/Cortland Cast Server.app/Contents/Resources/"
        echo -e "${BLUE}Converted and copied icon.icns${NC}"
    else
        echo -e "${YELLOW}Skipping icon copy - sips/iconutil not available${NC}"
    fi
fi

# Get file size
EXECUTABLE_SIZE=$(du -h "Releases/Cortland Cast Server.app/Contents/MacOS/CortlandCastServer" | cut -f1)

echo ""
echo -e "${GREEN}Build completed successfully!${NC}"
echo ""
echo -e "${GREEN}App bundle created:${NC} Cortland Cast Server.app/"
echo -e "${GREEN}Executable:${NC} Cortland Cast Server.app/Contents/MacOS/CortlandCastServer (${EXECUTABLE_SIZE})"
echo ""
echo -e "${BLUE}To run the server:${NC}"
echo -e "  open 'Cortland Cast Server.app'"
echo ""
echo -e "${YELLOW}Or run directly:${NC}"
echo -e "  ./'Releases/Cortland Cast Server.app/Contents/MacOS/CortlandCastServer'"
echo ""
echo -e "${YELLOW}Make sure Apple Music is installed and authorized.${NC}"
