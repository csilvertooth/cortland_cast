# Cortland Cast Server - Build and Packaging Makefile

.PHONY: all build release clean install uninstall help

# Default target
all: build

# Build debug version
build:
	swift build
	@echo "Debug build completed: .build/debug/CortlandCastServer"

# Build optimized release with app bundle in project directory
release: clean
	@echo "Building optimized release..."
	swift build --product CortlandCastServer --configuration release
	@echo "Creating app bundle..."
	@mkdir -p "Cortland Cast Server.app/Contents/MacOS"
	@mkdir -p "Cortland Cast Server.app/Contents/Resources"
	@echo "Copying executable..."
	cp ".build/arm64-apple-macosx/release/CortlandCastServer" "Cortland Cast Server.app/Contents/MacOS/"
	chmod +x "Cortland Cast Server.app/Contents/MacOS/CortlandCastServer"
	cp Info.plist "Cortland Cast Server.app/Contents/"
	@echo "App bundle created successfully"
	@ls -la "Cortland Cast Server.app/Contents/MacOS/"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build/
	rm -rf release/

# Install locally (for development)
install:
	swift build
	cp .build/debug/CortlandCastServer /usr/local/bin/CortlandCastServer
	@echo "Installed to /usr/local/bin/CortlandCastServer"

# Uninstall local install
uninstall:
	rm -f /usr/local/bin/CortlandCastServer
	@echo "Removed from /usr/local/bin/CortlandCastServer"

# Help
help:
	@echo "Cortland Cast Server Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build     - Build debug version"
	@echo "  release   - Build optimized release and create app bundle in current directory"
	@echo "  clean     - Clean build artifacts"
	@echo "  install   - Install locally (for development)"
	@echo "  uninstall - Remove local installation"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Example usage:"
	@echo "  make release    # Build release and create 'Cortland Cast Server.app'"
	@echo "  make build      # Quick debug build"
