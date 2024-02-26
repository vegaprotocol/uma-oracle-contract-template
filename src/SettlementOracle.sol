// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
  BaseOracle,
  IERC20,
  SafeERC20,
  Strings,
  OptimisticOracleV3Interface,
  ClaimAlreadySubmitted,
  BondOutOfRange
} from "./BaseOracle.sol";

contract SettlementOracle is BaseOracle {
  using SafeERC20 for IERC20;

  struct Identifier {
    uint64 liveness;
    IERC20 bondCurrency;
    uint256 minimumBond;
    uint256 maximumBond;
    string marketCode;
    string quoteName;
    string enactmentDate;
    string ipfsLink;
  }

  struct Data {
    uint256 price;
  }

  function claimText(Identifier memory identifier, Data memory data) public pure returns (bytes memory) {
    return abi.encodePacked(
      "Settling VEGA market ",
      identifier.marketCode,
      " settled in ",
      identifier.quoteName,
      " enacted on ",
      identifier.enactmentDate,
      ", to settle at ",
      Strings.toString(data.price),
      ".\n IPFS link to validation instructions: ",
      identifier.ipfsLink
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

  constructor(address _oracle) BaseOracle(_oracle) {}

  function submitClaim(Identifier calldata identifier, Data calldata data) public {
    return submitClaim(identifier, data, identifier.minimumBond, msg.sender);
  }

  function submitClaim(Identifier calldata identifier, Data calldata data, uint256 bondAmount) public {
    return submitClaim(identifier, data, bondAmount, msg.sender);
  }

  function submitClaim(Identifier calldata identifier, Data calldata data, uint256 bondAmount, address asserter) public {
    if (identifier.minimumBond > bondAmount || bondAmount > identifier.maximumBond) {
      revert BondOutOfRange(identifier.minimumBond, identifier.maximumBond, bondAmount);
    }

    bytes32 claimId = id(identifier);
    Claim storage claim = claims[claimId];
    if (claim.assertionId != 0) {
      revert ClaimAlreadySubmitted(claim.assertionId);
    }

    identifier.bondCurrency.approve(address(oracle), bondAmount);
    identifier.bondCurrency.safeTransferFrom(msg.sender, address(this), bondAmount);

    bytes memory text = claimText(identifier, data);
    address callbackRecipient = address(this);
    address escalationManager = address(0); // default

    bytes32 assertionId = oracle.assertTruth(
      text,
      asserter,
      callbackRecipient,
      escalationManager,
      identifier.liveness,
      identifier.bondCurrency,
      bondAmount,
      0,
      0
    );

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
