.PHONY: help deploy weth-deposit weth-balance weht-approve

ENV_FILE ?= .env

-include $(ENV_FILE)

help:
	@echo "Usage: make [ENV_FILE=.env] <target>"
	@echo ""
	@echo "Targets:"
	@echo "  deploy          Deploy the contract"
	
	@echo "  weth-deposit    Deposit WETH"
	@echo "			AMOUNT      Amount to deposit as integer or string, eg 1 ether, 500 gwei, 1000000000, 0x1"
	@echo "  weth-withdraw   Withdraw WETH"
	@echo "			AMOUNT      Amount to withdraw as integer or string, eg 1 ether, 500 gwei, 1000000000, 0x1"
	@echo "  weth-balance    Check WETH balance"
	@echo "  weth-approve    Approve WETH"
	@echo "			AMOUNT      Amount to approve as integer or string, eg 1 ether, 500 gwei, 1000000000, 0x1"
	@echo "			ADDRESS     Address to approve"
	@echo ""
	@echo "Examples:"
	@echo "  make weth-deposit AMOUNT='1 ether'"
	@echo "  make weth-balance"
	@echo "  make weth-approve AMOUNT='1 ether' ADDRESS='0x1234567890123456789012345678901234567890'"
	@echo ""
	@echo "Environment:"
	@echo "  CHAIN_ID										Chain ID, eg 1 for Ethereum Mainnet, 5 for Goerli"
	@echo "  CHAIN											Name of the chain as defined in foundry.toml"
	@echo "  ETH_RPC_URL								URL of a Ethereum RPC provider"
	@echo "  ETHERSCAN_API_KEY					API key for contract verification on Etherscan"
	@echo "  PRIVATE_KEY								Private key of the wallet to use for transactions"
	@echo "  WETH_ADDRESS								Address of the WETH contract"
	@echo "  UMA_OPTIMISTIC_ORACLE_V3		Address of the UMA Optimistic Oracle V3 contract"

weth-deposit:
	cast send \
		--chain-id $(CHAIN_ID) \
		--value $(AMOUNT) \
		--rpc-url $(CHAIN) \
		--private-key $(PRIVATE_KEY) \
		$(WETH_ADDRESS) \
		"deposit()"

weth-withdraw:
	cast send \
		--chain-id $(CHAIN_ID) \
		--rpc-url $(CHAIN) \
		--private-key $(PRIVATE_KEY) \
		$(WETH_ADDRESS) \
		"withdraw(uint256)" \
		$(AMOUNT)

weth-balance:
	cast call \
		--chain-id $(CHAIN_ID) \
		--rpc-url $(CHAIN) \
		$(WETH_ADDRESS) \
		"balanceOf(address)(uint256)" \
		`cast wallet address $(PRIVATE_KEY)`

weth-approve:
	cast send \
		--chain-id $(CHAIN_ID) \
		--rpc-url $(CHAIN) \
		--private-key $(PRIVATE_KEY) \
		$(WETH_ADDRESS) \
		"approve(address,uint256)" \
		$(ADDRESS) \
		$(AMOUNT)

deploy:
	forge script script/Deploy.s.sol:DeployScript \
		--chain-id $(CHAIN_ID) \
		--multi \
		--broadcast \
		--verify \
		--rpc-url $(CHAIN) \
		--private-key $(PRIVATE_KEY)
