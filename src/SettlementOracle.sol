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

/// @title SettlementOracle
/// @notice This contract serves as an oracle for setteling VEGA markets using the UMA Protocol and Optimistic Oracle v3.
/// @inheritdoc BaseOracle
contract SettlementOracle is BaseOracle {
  using SafeERC20 for IERC20;

  /// @notice `Identifier` values must match the exact values used in the VEGA market proposal. Any small deviation will result in any claims not being read correctly by VEGAs ethereum oracle functionality.
  /// @dev `Identifier` represents a unique set of human readable values that is used to generate an internal `bytes32` ID, often referred to as `claimId`.
  /// @dev The mix of properties should be values that are known at the time the VEGA market is proposed and must not overlap with any other past or future market.
  /// @dev `Identifier` can be considered a form of "commitment" that will be "revealed" in the future by someone making a claim.
  /// @param liveness The time in seconds that the claim will be open for dispute.
  /// @param bondCurrency The currency used as a bond to the claim. Must be an UMA approved token. The asserter must approve this contract to transfer the bond amount.
  /// @param minimumBond The minimum bond amount required to make a claim.
  /// @param maximumBond The maximum bond amount allowed to make a claim.
  /// @param marketCode The identifier of the VEGA market as per the VEGA market proposal.
  /// @param quoteName The name of the quote currency as per the VEGA market proposal.
  /// @param enactmentDate The date the VEGA market is enacted as per the VEGA market proposal. Should be ISO 8601 format.
  /// @param ipfsLink A link to the IPFS file containing the validation instructions.
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

  /// @notice `Data` represents structured data attached to a claim and readable by VEGA through the `getData` function.
  /// @param price The price at which the VEGA market is settled.
  struct Data {
    uint256 price;
  }

  /// @notice `claimText` is a helper function to generate the text that will be attached to the claim and must be human readable, and provide clear instructions on how to validate the claim.
  /// @param identifier The identifier of the claim.
  /// @param data The data of the claim.
  /// @return The text that will be attached to the claim.
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

  /// @notice `id` is a helper function to generate the `bytes32` ID of a claim.
  /// @param identifier The identifier of the claim.
  /// @return The `bytes32` ID of the claim.
  function id(Identifier calldata identifier) public view returns (bytes32) {
    return _id(abi.encode(identifier));
  }

  /// @notice `getData` is the primary function to read the structured data attached to a claim.
  /// @notice This function is more expensive to call on-chaon than `getCachedData` as it reads the claim resolution directly from the OOv3 contract. This means it will always return the most up to date information, without needing callback from UMA OOv3.
  /// @param identifier The identifier of the claim.
  /// @return A tuple containing the result of the claim, and the price at which the VEGA market is settled.
  function getData(Identifier calldata identifier) public returns (bool, uint256) {
    Claim memory claim = _getClaim(id(identifier));
    bool result = _getAssertionResult(claim.assertionId);

    Data memory data = abi.decode(claim.data, (Data));

    return (result, data.price);
  }

  /// @notice `getCachedData` is a helper function to read the structured data attached to a claim. The result is based on data stored in this contract only and may not have the most up to date resolution from UMA OOv3.
  /// @param identifier The identifier of the claim.
  /// @return A tuple containing the result of the claim, and the price at which the VEGA market is settled.
  function getCachedData(Identifier calldata identifier) public view returns (bool, uint256) {
    Claim memory claim = _getClaim(id(identifier));
    Data memory data = abi.decode(claim.data, (Data));

    return (claim.result, data.price);
  }

  constructor(address _oracle) BaseOracle(_oracle) {}

  /// @notice Submit a claim to the oracle. This function will use the minimum bond amount required to make a claim and the sender as the asserter. This means the bond will be returned to the sender if successfully resolved.
  /// @notice You must approve the bond currency to this contract before calling this function.
  /// @notice A claim can only be submitted once for each `Identifier`, except if the claim is disputed. In that case, a new claim can immediately be submitted.
  /// @param identifier The identifier of the claim. The provided identifier must match the exact values used in the VEGA market proposal.
  /// @param data The data of the claim.
  function submitClaim(Identifier calldata identifier, Data calldata data) public {
    return submitClaim(identifier, data, identifier.minimumBond, msg.sender);
  }

  /// @notice Submit a claim to the oracle. This function lets you specify the bond amount, withing the minimum and maximum bond range, and the sender as the asserter. This means the bond will be returned to the sender if successfully resolved.
  /// @notice You must approve the bond currency to this contract before calling this function.
  /// @notice A claim can only be submitted once for each `Identifier`, except if the claim is disputed. In that case, a new claim can immediately be submitted.
  /// @param identifier The identifier of the claim. The provided identifier must match the exact values used in the VEGA market proposal.
  /// @param data The data of the claim.
  function submitClaim(Identifier calldata identifier, Data calldata data, uint256 bondAmount) public {
    return submitClaim(identifier, data, bondAmount, msg.sender);
  }

  /// @notice Submit a claim to the oracle. This function lets you specify the bond amount, withing the minimum and maximum bond range, and the asserter. The asserter will recieve the bond back if the claim is successfully resolved.
  /// @notice You must approve the bond currency to this contract before calling this function.
  /// @notice A claim can only be submitted once for each `Identifier`, except if the claim is disputed. In that case, a new claim can immediately be submitted.
  /// @param identifier The identifier of the claim. The provided identifier must match the exact values used in the VEGA market proposal.
  /// @param data The data of the claim.
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
      bytes32("ASSERT_TRUTH"),
      0
    );

    claim.assertionId = assertionId;
    claim.data = abi.encode(data);

    assertionToClaimId[assertionId] = claimId;

    emit Submitted(claimId, assertionId);
  }

  /// @notice Finalize a claim by settling the associated assertion, and release the bond.
  /// @notice This function is more expensive to call than setteling directly with the OOv3 contract or through the UMA dApp. However it provides the convenience of resolving the assertionId from the claim identifier.
  /// @param identifier The identifier of the claim to finalize.
  function finalizeClaim(Identifier calldata identifier) external {
    bytes32 claimId = id(identifier);
    return _finalizeClaim(claimId);
  }
}
