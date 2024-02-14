.PHONY: deploy

ENV_FILE ?= .env

-include $(ENV_FILE)

deploy:
	forge script script/Deploy.s.sol:DeployScript \
		--chain-id $(CHAIN_ID) \
		--multi \
		--broadcast \
		--verify \
		--rpc-url $(CHAIN) \
		--private-key $(PRIVATE_KEY)
