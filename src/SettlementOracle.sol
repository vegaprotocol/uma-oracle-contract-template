// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {BaseOracle, IERC20, OptimisticOracleV3Interface} from "./BaseOracle.sol";

struct Settlement {
  bytes32 identifier;
  bytes32 assertionId;
  uint256 timestamp;
  bool resolved;
  uint256 price;
}

struct Identifier {
  string marketId;
}

contract SettlementOracle is BaseOracle {
  using SafeERC20 for IERC20;

  IERC20 public immutable bondCurrency;

  // identifier => Settlement
  mapping(bytes32 => Settlement) public settlements;

  constructor(address _oracle, address _bondCurrency) {
    oracle = OptimisticOracleV3Interface(_oracle);
    bondCurrency = IERC20(_bondCurrency);
  }

  function getSettlementPrice(Identifier calldata _id) public view returns (uint256) {
    bytes32 identifier = id(_id);
    Settlement storage settlement = settlements[identifier];
    if (settlement.resolved == false) {
      return 0;
    }

    return settlement.price;
  }

  function id(Identifier calldata _id) public pure returns (bytes32) {
    return keccak256(abi.encode(_id));
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

  function settle(Identifier calldata _id, uint256 settlementPrice, address asserter) external {
    asserter = asserter == address(0) ? msg.sender : asserter;

    bytes32 identifier = id(_id);
    if (settlements[identifier].identifier != bytes32(0)) {
      revert("Settlement already submitted");
    }

    uint256 bond = this.getBondAmount();
    bondCurrency.safeTransferFrom(asserter, address(this), bond);
    bondCurrency.approve(address(oracle), bond);

    bytes memory claim = abi.encodePacked(
      "Asserting settlement price for market: ",
      _id.marketId,
      " with price: ",
      Strings.toString(settlementPrice)
    );

    bytes32 ooId = oracle.defaultIdentifier();
    bytes32 assertionId = super._assert(claim, asserter, ooId);

    settlements[identifier] = Settlement({
      identifier: identifier,
      assertionId: assertionId,
      timestamp: block.timestamp,
      resolved: false,
      price: settlementPrice
    });
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

    require(identifier != bytes32(0), "SettlementOracle: assertionId not found");
    Settlement storage settlement = settlements[identifier];

    if (assertedTruthfully == false) {
      delete assertionIds[assertionId];
      delete settlements[identifier];
      emit Disputed(assertionId);
      return;
    }

    settlement.resolved = true;
    emit Completed(assertionId);
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is disputed.
   * @param assertionId The identifier of the assertion that was disputed.
   */
  function assertionDisputedCallback(bytes32 assertionId) external {
    // Do nothing
  }
}
