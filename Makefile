SHELL := /bin/zsh
RUST_BIN := $(HOME)/.rustup/toolchains/stable-aarch64-apple-darwin/bin
export PATH := $(RUST_BIN):$(PATH)

.PHONY: bootstrap rust-fmt rust-lint rust-test postgres-test swift-build swift-test project mac-build ios-build ios-test test clean

bootstrap: project
	swift package resolve

rust-fmt:
	cargo fmt --all -- --check

rust-lint:
	cargo clippy --workspace --all-targets -- -D warnings

rust-test:
	cargo test --workspace

postgres-test:
	./scripts/test-plan-store.sh

swift-build:
	swift build

swift-test:
	swift test

project:
	xcodegen generate

mac-build: project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-macOS \
		-configuration Debug -destination 'platform=macOS' \
		build CODE_SIGNING_ALLOWED=NO

ios-build: project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS \
		-configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17e' \
		build CODE_SIGNING_ALLOWED=NO

ios-test: project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS \
		-configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17e' \
		test CODE_SIGNING_ALLOWED=NO

test: rust-fmt rust-lint rust-test postgres-test swift-test ios-test

clean:
	rm -rf .build target
