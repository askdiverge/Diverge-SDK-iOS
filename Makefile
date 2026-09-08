.PHONY: help sync-version check-version ios-test ios-lint docs-docc install-hooks ci-local uitest
help:
	@echo "Diverge SDK iOS — see README"
	@echo "  make uitest   stand-in XCUITests (needs iOS Simulator)"
sync-version:
	./scripts/sync-version.sh
check-version:
	./scripts/check-version.sh
ios-test: check-version
	swift test
ios-lint:
	swiftlint lint --strict
docs-docc:
	./scripts/build-docs-site.sh
install-hooks:
	./scripts/install-git-hooks.sh
ci-local:
	./scripts/ci-local.sh
uitest:
	./Tests/Standin/run-uitests.sh
