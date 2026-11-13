SHELL := /bin/zsh
RUST_BIN := $(HOME)/.rustup/toolchains/stable-aarch64-apple-darwin/bin
CARGO_HOME := $(CURDIR)/.build/cargo-home
CARGO := $(RUST_BIN)/cargo
RUST_ENV := PATH="$(RUST_BIN):$$PATH" CARGO_HOME="$(CARGO_HOME)"
.PHONY: prepare-cargo-home bootstrap rust-fmt rust-lint rust-test ffi swift-build swift-test project mac-build ios-build ios-test test verify clean

prepare-cargo-home:
	@mkdir -p "$(CARGO_HOME)"
	@if [[ ! -e "$(CARGO_HOME)/registry" && -d "$(HOME)/.cargo/registry" ]]; then ln -s "$(HOME)/.cargo/registry" "$(CARGO_HOME)/registry"; fi

bootstrap: prepare-cargo-home ffi project
	swift package resolve

rust-fmt:
	$(RUST_ENV) $(CARGO) fmt --all -- --check

rust-lint: prepare-cargo-home
	$(RUST_ENV) $(CARGO) clippy --workspace --all-targets -- -D warnings

rust-test: prepare-cargo-home
	$(RUST_ENV) $(CARGO) test --workspace

ffi:
	$(RUST_ENV) ./scripts/build-ffi.sh all

swift-build:
	swift build

swift-test: prepare-cargo-home ffi
	KSHIFT_FFI_PATH="$(CURDIR)/.build/ffi/macos/libkshift_ffi.dylib" swift test

project:
	xcodegen generate

mac-build: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme KshiftMac -configuration Debug -destination 'platform=macOS' build

ios-build: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme KshiftIOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

ios-test: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme KshiftIOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

test: rust-fmt rust-lint rust-test swift-test
	KSHIFT_SKIP_XCODE_TESTS=1 ./scripts/verify.sh

verify: test
	./scripts/verify.sh

clean:
	rm -rf .build target
