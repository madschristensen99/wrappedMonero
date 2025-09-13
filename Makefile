.PHONY: all build test clean deploy

# Main targets
all: build

build:
	@echo "Building all components..."
	cd guest && cargo build --release --target riscv32im-risc0-zkvm-elf
	cd fhe-engine && cargo build --release
	cd relay && cargo build --release
	cd contract && npm install && npm run build
	cd wallet && npm install && npm run build

test:
	@echo "Running tests..."
	cd guest && cargo test
	cd fhe-engine && cargo test
	cd relay && cargo test
	cd contract && npm test
	cd tests && python __init__.py && python test_zkvm.py

# Development targets
dev-relay:
	cd relay && cargo watch -x run

dev-fhe:
	cd fhe-engine && cargo watch -x run

# Docker targets
docker-build:
	docker-compose build

docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

# Contract targets
deploy-contract:
	cd contract && npm run deploy

# Wallet targets
wallet-build:
	cd wallet && npm run build

wallet-generate:
	cd wallet && npm run build && ./dist/cli.js generate

# Cleanup
clean:
	cargo clean
	rm -rf target/
	rm -rf contract/node_modules
	rm -rf wallet/node_modules
	rm -rf wallet/dist
	docker-compose down -v
	rm -rf monero_data relay_data fhe_keys

docker-clean:
	docker image prune -f
	docker volume prune -f

# Documentation
docs:
	@echo "Documentation available in specification.md"
	@echo "API reference in relay/src/main.rs"
	@echo "Contract docs in contract/contracts/wxMR.sol"

# Help
help:
	@echo "Available targets:"
	@echo "  build         - Build all components"
	@echo "  test          - Run all tests"
	@echo "  dev-relay     - Start relay in dev mode"
	@echo "  dev-fhe       - Start FHE engine in dev mode"
	@echo "  docker-build  - Build Docker images"
	@echo "  docker-up     - Start infrastructure with Docker"
	@echo "  deploy-contract - Deploy smart contract"
	@echo "  wallet-build  - Build wallet CLI"
	@echo "  clean         - Clean all build artifacts"
	@echo "  help          - Show this help"