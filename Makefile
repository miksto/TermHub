.PHONY: build run test generate

generate: ## Regenerate Xcode project from project.yml
	./scripts/regenerate-project.sh

build: ## Build the app
	./scripts/build.sh

run: ## Build and launch the app
	./scripts/build-and-run.sh

test: ## Run the test suite
	./scripts/test.sh
