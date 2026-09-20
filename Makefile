# Lyra — voice computer use for macOS, and a small companion app for iPhone.
.DEFAULT_GOAL := help

.PHONY: help setup mac run ios ios-run ios-device test clean

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  make %-10s %s\n", $$1, $$2}'

setup: ## Keys from .env into the Keychain, then build, install and launch the Mac app
	@scripts/setup.sh

mac: ## Build and install the Mac app into ~/Applications
	@scripts/mac.sh

run: ## Build, install and launch the Mac app
	@scripts/mac.sh --run

ios: ## Build the iPhone app for the simulator
	@scripts/ios.sh

ios-run: ## Build the iPhone app and launch it in a simulator
	@scripts/ios.sh run

ios-device: ## Build signed and install onto the iPhone plugged in over USB
	@scripts/ios.sh device

test: ## Run the Mac tests
	@xcrun swift test --package-path mac

clean: ## Remove build output
	@rm -rf mac/.build ios/build
	@xcodebuild -project ios/Lyra.xcodeproj -scheme Lyra clean >/dev/null 2>&1 || true
	@echo "Cleaned."
