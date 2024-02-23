// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
  BaseOracle, IERC20, SafeERC20, Strings, OptimisticOracleV3Interface, ClaimAlreadySubmitted
} from "./BaseOracle.sol";

contract SettlementOracle is BaseOracle {
  using SafeERC20 for IERC20;

  struct Identifier {
    string marketCode;
    string quoteName;
    string enactmentDate;
  }

  struct Data {
    uint256 price;
  }

  function claimText(Identifier memory identifier, Data memory data) public pure returns (bytes memory) {
    return abi.encodePacked(
      "Claiming ",
      identifier.marketCode,
      " settled in ",
      identifier.quoteName,
      " enacted on ",
      identifier.enactmentDate,
      ", to settle at ",
      Strings.toString(data.price)
    );
  }

  function id(Identifier calldata identifier) public view returns (bytes32) {
    return _id(abi.encode(identifier));
  }

  function getData(Identifier calldata identifier) public view returns (bool, uint256) {
    Claim memory claim = _getClaim(id(identifier));
    bool result = _getAssertionResult(claim.assertionId);

    Data memory data = abi.decode(claim.data, (Data));

    return (result, data.price);
  }

  function getCachedData(Identifier calldata identifier) public view returns (bool, uint256) {
    Claim memory claim = _getClaim(id(identifier));
    Data memory data = abi.decode(claim.data, (Data));

    return (claim.result, data.price);
  }

  constructor(address _oracle, address _bondCurrency, uint64 _liveness)
    BaseOracle(_oracle, _bondCurrency, _liveness)
  {}

  function submitClaim(Identifier calldata identifier, Data calldata data) external {
    bytes32 claimId = id(identifier);
    Claim storage claim = claims[claimId];
    if (claim.assertionId != 0) {
      revert ClaimAlreadySubmitted(claim.assertionId);
    }

    uint256 bondAmount = oracle.getMinimumBond(address(bondCurrency));
    bondCurrency.safeTransferFrom(msg.sender, address(this), bondAmount);

    bytes memory text = claimText(identifier, data);
    address asserter = msg.sender;
    address callbackRecipient = address(this);
    address escalationManager = address(0); // default

    bytes32 assertionId =
      oracle.assertTruth(text, asserter, callbackRecipient, escalationManager, liveness, bondCurrency, bondAmount, 0, 0);

    claim.assertionId = assertionId;
    claim.data = abi.encode(data);

    assertionToClaimId[assertionId] = claimId;

    emit Submitted(claimId, assertionId);
  }

  /**
   * @notice Finalize a claim by settling the associated assertion, and release the bond.
   * @notice This function is more expensive to call than setteling directly with the OOv3 contract or through the UMA dApp. However it provides the convenience of resolving the assertionId from the claim identifier.
   * @param identifier The identifier of the claim to finalize.
   */
  function finalizeClaim(Identifier calldata identifier) external {
    bytes32 claimId = id(identifier);
    return _finalizeClaim(claimId);
  }
}
