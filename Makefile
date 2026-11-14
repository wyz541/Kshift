SHELL := /bin/zsh
RUST_BIN := $(HOME)/.rustup/toolchains/stable-aarch64-apple-darwin/bin
CARGO_HOME := $(CURDIR)/.build/cargo-home
CARGO := $(RUST_BIN)/cargo
RUST_ENV := PATH="$(RUST_BIN):$$PATH" CARGO_HOME="$(CARGO_HOME)"
BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
MACOS_APP := $(DERIVED_DATA)/Build/Products/Debug/Kshift-macOS.app
IOS_APP := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/Kshift-iOS.app
DRY_RUN ?= 0

.PHONY: prepare-cargo-home bootstrap rust-fmt rust-lint rust-test ffi swift-build swift-test project mac-build ios-build ios-test live-ui-e2e test verify app-paths clean-build check-build-governance legacy-deriveddata-manifest r4-load preview-lifecycle launchd-restart clean

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

ffi: prepare-cargo-home
	$(RUST_ENV) ./scripts/build-ffi.sh all

swift-build:
	swift build

swift-test: prepare-cargo-home
	$(RUST_ENV) ./scripts/build-ffi.sh macos
	KSHIFT_FFI_PATH="$(CURDIR)/.build/ffi/macos/libkshift_ffi.a" swift test

project:
	xcodegen generate

mac-build: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-macOS -configuration Debug -destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" build

ios-build: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath "$(DERIVED_DATA)" build

ios-test: ffi project
	xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath "$(DERIVED_DATA)" test

live-ui-e2e:
	KSHIFT_CARGO_OFFLINE=1 ./scripts/run-live-ui-e2e.sh

r4-load:
	KSHIFT_LOAD_DURATION_SECS="$${KSHIFT_LOAD_DURATION_SECS:-1800}" ./scripts/run-load-evidence.sh

preview-lifecycle: ios-build mac-build
	./scripts/test-preview-lifecycle.sh

launchd-restart:
	./scripts/test-launchd-restart.sh

test: rust-fmt rust-lint rust-test swift-test
	KSHIFT_SKIP_XCODE_TESTS=1 ./scripts/verify.sh

verify: test
	./scripts/verify.sh

app-paths:
	@printf 'macOS: %s (%s)\n' "$(MACOS_APP)" "$(if $(wildcard $(MACOS_APP)),present,missing)"
	@printf 'iOS:   %s (%s)\n' "$(IOS_APP)" "$(if $(wildcard $(IOS_APP)),present,missing)"

clean-build:
	@./scripts/clean-build.sh $(if $(filter 1 true yes,$(DRY_RUN)),--dry-run,)

check-build-governance:
	@./scripts/check-build-governance.py

legacy-deriveddata-manifest:
	@./scripts/list-legacy-deriveddata.sh

clean: clean-build
	rm -rf .build target
