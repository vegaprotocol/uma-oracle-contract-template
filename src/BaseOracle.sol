// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptimisticOracleV3Interface} from
  "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

abstract contract BaseOracle {
  event Submitted(bytes32 indexed identifier);
  event Completed(bytes32 indexed identifier);
  event Disputed(bytes32 indexed identifier);

  OptimisticOracleV3Interface immutable oracle;

  // assertionId => identifier
  mapping(bytes32 => bytes32) public assertionIds;

  function getBondCurrency() public virtual returns (IERC20);
  function getBondAmount() public virtual returns (uint256);
  function getLiveness() public virtual returns (uint64);

  function _assert(bytes memory claim, address asserter, bytes32 identifier) internal returns (bytes32 assertionId) {
    address callbackRecipient = address(this);
    address escalationManager = address(0); // default
    uint64 liveness = this.getLiveness();
    IERC20 currency = this.getBondCurrency();
    uint256 bond = this.getBondAmount();
    bytes32 domainId = bytes32(0);

    assertionId = oracle.assertTruth(
      claim, asserter, callbackRecipient, escalationManager, liveness, currency, bond, identifier, domainId
    );
  }
}
