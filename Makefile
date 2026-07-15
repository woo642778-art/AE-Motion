SHELL := /bin/bash

.PHONY: bootstrap doctor generate test-core test-contracts build-ios test-ios verify

bootstrap:
	bash scripts/bootstrap-macos.sh

doctor:
	bash scripts/doctor-macos.sh

generate:
	bash scripts/generate-test-host.sh

test-core:
	swift test

test-contracts:
	python3 scripts/test-normalize-effect-search-metadata.py -v
	python3 scripts/test-preset-application-host-error-isolation.py
	python3 scripts/test-ui-integration-contract.py
	python3 scripts/test-category-collection-proxy-isolation.py
	python3 scripts/test-category-proxy-indexpath-forwarding.py

build-ios:
	bash scripts/build-ios-framework.sh

test-ios:
	bash scripts/test-ios-simulator.sh

verify: test-core test-contracts build-ios test-ios
