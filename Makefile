.PHONY: build run test generate build-mcp install-mcp

generate: ## Regenerate Xcode project from project.yml
	./scripts/regenerate-project.sh

build: ## Build the app
	./scripts/build.sh

run: ## Build and launch the app
	./scripts/build-and-run.sh

test: ## Run the test suite
	./scripts/test.sh

build-mcp: ## Build the MCP server
	@set -o pipefail; xcodebuild \
		-project TermHub.xcodeproj \
		-scheme TermHubMCP \
		-configuration Release \
		build 2>&1 \
		| grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' || true

install-mcp: build-mcp ## Build and install the MCP server to ~/.local/bin
	@mkdir -p ~/.local/bin
	@build_dir=$$(xcodebuild \
		-project TermHub.xcodeproj \
		-scheme TermHubMCP \
		-configuration Release \
		-showBuildSettings 2>/dev/null \
		| grep ' BUILT_PRODUCTS_DIR' \
		| awk '{print $$NF}'); \
	test -f "$$build_dir/termhub-mcp"; \
	cp "$$build_dir/termhub-mcp" ~/.local/bin/termhub-mcp; \
	codesign --force --sign - --timestamp=none ~/.local/bin/termhub-mcp
	@echo "Installed termhub-mcp to ~/.local/bin/termhub-mcp"
