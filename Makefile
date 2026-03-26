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
	xcodebuild \
		-workspace TermHub.xcodeproj/project.xcworkspace \
		-scheme TermHubMCP \
		-configuration Release \
		build 2>&1 \
		| grep -E '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|fatal)' \
		|| echo "Build completed with no issues"

install-mcp: build-mcp ## Build and install the MCP server to ~/.local/bin
	@mkdir -p ~/.local/bin
	@build_dir=$$(xcodebuild \
		-workspace TermHub.xcodeproj/project.xcworkspace \
		-scheme TermHubMCP \
		-configuration Release \
		-showBuildSettings 2>/dev/null \
		| grep ' BUILT_PRODUCTS_DIR' \
		| awk '{print $$NF}'); \
	cp "$$build_dir/termhub-mcp" ~/.local/bin/termhub-mcp
	@echo "Installed termhub-mcp to ~/.local/bin/termhub-mcp"
