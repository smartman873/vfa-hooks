.PHONY: bootstrap deploy-local deploy-sepolia deploy-reactive demo-local demo-sepolia demo-testnet-live test build frontend-build coverage verify-commits

bootstrap:
	./scripts/bootstrap.sh

deploy-local:
	./scripts/deploy_local.sh

deploy-sepolia:
	./scripts/deploy_sepolia.sh

deploy-reactive:
	./scripts/deploy_reactive.sh

demo-local:
	./scripts/demo_local.sh

demo-sepolia:
	./scripts/demo_sepolia.sh

demo-testnet-live:
	./scripts/demo_testnet_live.sh

build:
	cd contracts && forge build
	cd reactive && forge build

test:
	cd contracts && forge test --offline
	cd reactive && forge test --offline

coverage:
	cd contracts && forge coverage --offline --exclude-tests --no-match-coverage "script|test|lib|deps"
	cd reactive && forge coverage --offline --exclude-tests --no-match-coverage "script|test|lib|deps"

frontend-build:
	cd frontend && pnpm install && pnpm build

verify-commits:
	./scripts/verify_commits.sh
