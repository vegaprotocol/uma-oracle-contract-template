# Vega/UMA Oracles 

> Example contracts showcasing how UMA Optimistic Oracles can be used for Vega market termination and settlement

## Installation

This example repository uses Foundry to build and execute Solidity scripts.
Please see the Foundry Book for installation instructions:

https://book.getfoundry.sh/

## Usage

### Modify

Two sample oracles are included; `TerminationOracle` and `SettlementOracle`.
Both work in similar fashion. When proposing a market on Vega, 
`TerminationOracle` could be used as an `external` oracle for 
`dataSourceSpecForTradingTermination`, while `SettlementOracle`
could be used as an `external` oracle for `dataSourceSpecForSettlementData`.

Both contracts have a "trigger" function, respectively `submitClaim`.
Calling this functios require the "asserter" to place a bond. This bond
acts as an incentive in the UMA system for the asserter to act truthfully.
In case of a dispute this bond could be lost, or if a dispute is overturned
could grow. Most of the time, assertions are assumed not to be disputed,
hence the "Optimistic" part. This bond must be paid in an UMA approved
currency, and is defined by the `bondCurrency` and `bondAmount` on
the contracts in this repository.

Upon placing an assertion (eg. to terminate) a claim is submitted to UMA,
and can be seen in the Oracle dApp (https://oracle.uma.xyz/).
Inside the contracts of this repository a `struct` is stored containing
metadata about the assertion, and it's resolution.

Identifiers to look up the unique structs is itself a struct in the
examples. This makes it possible to define them from more user friendly
data such as a market name, a sequence number or any combination of fields.

Upon a final result from UMA, the contracts will get a callback when either
the original asserter claims back their bond, or a disputer claims their 
reward, which will trigger an update on the stored data in the example 
contracts, and the result can be read via `getData`.

[`sample-proposal.json`](sample-proposal.json) contains a partial Vega
market proposal for contracts deployed on the Goerli network.

Small, selective ABIs can be generated with `forge inspect` and `jq`.
Here the `getTermination` from `TerminationOracle` is filtered out and
encoded as a JSON string in the format expected by Vega:

```shell
forge inspect TerminationOracle abi | jq '[.[] | select(.name == "getData")] | tostring' --monochrome-output --compact-output
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy

Modify the included `.env` file, filling in missing variables. Here's an 
example for Goerli Testnet:

```make
export CHAIN=goerli
export CHAIN_ID=5
export ETH_RPC_URL=https://goerli.infura.io/v3/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
export ETHERSCAN_API_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

export WETH_ADDRESS=0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6
export UMA_OPTIMISTIC_ORACLE_V3=0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB

export PRIVATE_KEY=0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

The included `Makefile` has a phony `deploy` target that will wrap 1 Ether,
deploy the two sample oracles and approve both to spend 0.5 WETH for bonds:

```shell
$ make deploy
```

## License

[MIT](LICENSE)
