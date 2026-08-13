.PHONY: help sync-version check-version ios-test ios-lint docs-docc sample-ios-open install-hooks ci-local

help:
	@echo "Diverge SDK iOS make targets:"
	@echo "  make install-hooks     - Enable local pre-commit Git hooks"
	@echo "  make ci-local          - Run full local iOS CI"
	@echo "  make sync-version      - Write VERSION into generated sources/docs"
	@echo "  make check-version     - Fail if VERSION drifts from synced files"
	@echo "  make ios-test          - Run Swift package tests (macOS host)"
	@echo "  make ios-lint          - SwiftLint + SwiftFormat lint"
	@echo "  make docs-docc         - Build DocC (SDK+UI) + Docs/site into site-dist/"
	@echo "  make sample-ios-open   - Open the iOS sample in Xcode"

install-hooks:
	./scripts/install-git-hooks.sh

ci-local:
	./scripts/ci-local.sh ios

sync-version:
	./scripts/sync-version.sh

check-version:
	./scripts/check-version.sh

ios-test: check-version
	swift test

ios-lint:
	swiftlint lint --strict
	swiftformat --lint .

docs-docc:
	./scripts/build-docs-site.sh

sample-ios-open:
	open Samples/iOS/DivergeSample.xcodeproj
