GO      ?= go
MODULE  := $(shell $(GO) list -m)
VERSION ?=

.DEFAULT_GOAL := help

.PHONY: help ci tidy verify vet test lint lint-fix fmt audit
.PHONY: check-version check-clean check-main check-tag-free
.PHONY: tag release publish

## help: Show this help
help:
	@echo "Usage: make [target]"
	@echo "       make tag|release|publish VERSION=v0.1.0"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) | column -t -s ':' | sed -e 's/^/ /'

## ci: Run the local CI gate (tidy, verify, vet, lint, test, govulncheck)
ci: tidy verify vet lint test audit

## tidy: go mod tidy and fail if go.mod/go.sum would change
tidy:
	$(GO) mod tidy
	git diff --exit-code -- go.mod
	@if [ -f go.sum ]; then git diff --exit-code -- go.sum; fi

## verify: Check module checksums and that the package builds
verify:
	$(GO) mod verify
	$(GO) build ./...

## vet: Run go vet
vet:
	$(GO) vet ./...

## test: Run tests with race detector (same flags as GitHub Actions)
test:
	$(GO) test -v -race -shuffle=on -coverprofile=coverage.out ./...

## lint: Run golangci-lint
lint:
	golangci-lint run --timeout 5m ./...

## lint-fix: Run golangci-lint with auto-fix
lint-fix:
	golangci-lint run --fix --timeout 5m ./...

## fmt: Format with golangci-lint
fmt:
	golangci-lint fmt ./...

## audit: Run govulncheck
audit:
	govulncheck ./...

check-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "VERSION is required, e.g. make tag VERSION=v0.1.0" >&2; \
		exit 1; \
	fi
	@if ! echo "$(VERSION)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$$'; then \
		echo "VERSION must be semver with a v prefix, e.g. v0.1.0" >&2; \
		exit 1; \
	fi

check-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "working tree is dirty; commit or stash first" >&2; \
		exit 1; \
	fi

check-main:
	@if [ "$$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then \
		echo "must be on main to tag or release" >&2; \
		exit 1; \
	fi

check-tag-free: check-version
	@if git show-ref --tags --verify --quiet "refs/tags/$(VERSION)"; then \
		echo "tag $(VERSION) already exists locally" >&2; \
		exit 1; \
	fi
	@if git ls-remote --exit-code --tags origin "refs/tags/$(VERSION)" >/dev/null 2>&1; then \
		echo "tag $(VERSION) already exists on origin; never move a published tag" >&2; \
		exit 1; \
	fi

## tag: Create and push annotated tag VERSION (VERSION=v0.1.0)
tag: check-version check-main check-clean check-tag-free ci
	git tag -a "$(VERSION)" -m "$(MODULE) $(VERSION)"
	git push origin "refs/tags/$(VERSION)"

## release: Tag, create a GitHub Release, and publish to the module proxy
release: tag
	gh release create "$(VERSION)" --title "$(VERSION)" --generate-notes
	$(MAKE) publish VERSION=$(VERSION)

## publish: Ask proxy.golang.org / pkg.go.dev to index VERSION (tag must be on origin)
publish: check-version
	GOPROXY=proxy.golang.org $(GO) list -m "$(MODULE)@$(VERSION)"
	@echo "indexed $(MODULE)@$(VERSION)"
	@echo "docs: https://pkg.go.dev/$(MODULE)@$(VERSION)"
