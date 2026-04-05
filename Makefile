.PHONY: help build run test clean lint format install release notarize

# Default target
help:
	@echo "SomaFM Player - Development Commands"
	@echo ""
	@echo "  make build     - Build debug version"
	@echo "  make run       - Build and run the app"
	@echo "  make test      - Run tests"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make lint      - Run SwiftLint"
	@echo "  make format    - Auto-fix SwiftLint issues"
	@echo "  make install   - Build and install to /Applications"
	@echo "  make release   - Build release app bundle with ZIP"
	@echo "  make notarize  - Build, sign, notarize, and create ZIP"
	@echo ""

# Build debug version
build:
	swift build

# Run the app
run: build
	.build/debug/SomaFM

# Run tests
test:
	swift test

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build build

# Run SwiftLint
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi

# Auto-fix SwiftLint issues
format:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --fix && swiftlint; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi

# Build and install to Applications
install:
	@echo "🔨 Building and installing SomaFM..."
	@./scripts/create-app-bundle.sh --skip-clean
	@if [ -d "/Applications/SomaFM Menu Bar Player.app" ]; then \
		echo "⚠️  Removing existing installation..."; \
		rm -rf "/Applications/SomaFM Menu Bar Player.app"; \
	fi
	@cp -r "build/SomaFM Menu Bar Player.app" /Applications/
	@echo "✅ Installed to /Applications/SomaFM Menu Bar Player.app"

# Build release version with ZIP
release:
	./scripts/create-app-bundle.sh --zip

# Build, sign, notarize, and package
notarize:
	./scripts/create-app-bundle.sh --zip --notarize
