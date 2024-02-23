// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {BaseOracle, IERC20, OptimisticOracleV3Interface} from "./BaseOracle.sol";

struct Termination {
  bytes32 identifier;
  bytes32 assertionId;
  uint256 timestamp;
  bool resolved;
}

contract TerminationOracle is BaseOracle {
  using SafeERC20 for IERC20;

  IERC20 public immutable bondCurrency;

  // identifier => Termination
  mapping(bytes32 => Termination) public terminations;

  constructor(address _oracle, address _bondCurrency) {
    oracle = OptimisticOracleV3Interface(_oracle);
    bondCurrency = IERC20(_bondCurrency);
  }

  function getTermination(string calldata marketId) public view returns (bool) {
    bytes32 identifier = id(marketId);
    return terminations[identifier].resolved;
  }

  function id(string calldata marketId) public pure returns (bytes32) {
    return keccak256(abi.encode(marketId));
  }

  function getBondCurrency() public view override returns (IERC20) {
    return bondCurrency;
  }

  function getBondAmount() public view override returns (uint256) {
    return oracle.getMinimumBond(address(this.getBondCurrency()));
  }

  function getLiveness() public pure override returns (uint64) {
    return 2 minutes;
  }

  function terminate(string calldata marketId, address asserter) external {
    asserter = asserter == address(0) ? msg.sender : asserter;

    bytes32 identifier = id(marketId);
    if (terminations[identifier].identifier != bytes32(0)) {
      revert("Termination already submitted");
    }

    uint256 bond = this.getBondAmount();
    bondCurrency.safeTransferFrom(asserter, address(this), bond);
    bondCurrency.approve(address(oracle), bond);

    bytes memory claim = abi.encodePacked("Asserting termination for market: ", marketId);

    bytes32 ooId = oracle.defaultIdentifier();
    bytes32 assertionId = super._assert(claim, asserter, ooId);

    terminations[identifier] =
      Termination({identifier: identifier, assertionId: assertionId, timestamp: block.timestamp, resolved: false});
    assertionIds[assertionId] = identifier;

    emit Submitted(identifier);
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved.
   * @param assertionId The identifier of the assertion that was resolved.
   * @param assertedTruthfully Whether the assertion was resolved as truthful or not.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {
    require(msg.sender == address(oracle));
    bytes32 identifier = assertionIds[assertionId];

    require(identifier != bytes32(0), "TerminationOracle: assertionId not found");

    if (assertedTruthfully == false) {
      delete assertionIds[assertionId];
      delete terminations[identifier];
      emit Disputed(assertionId);
      return;
    }

    Termination storage termination = terminations[identifier];
    termination.resolved = true;
    emit Completed(identifier);
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is disputed.
   * @param assertionId The identifier of the assertion that was disputed.
   */
  function assertionDisputedCallback(bytes32 assertionId) external {
    // Do nothing
  }
}
