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
import {SettlementOracle} from "./SettlementOracle.sol";

contract TerminationOracle is BaseOracle {
  using SafeERC20 for IERC20;

  struct Identifier {
    IERC20 bondCurrency;
    uint256 minimumBond;
    uint256 maximumBond;
    uint64 liveness;
    string marketCode;
    string quoteName;
    string enactmentDate;
    string ipfsLink;
    SettlementOracle conditionalSettlementOracle;
  }

  struct Data {
    uint256 terminationTimestamp;
  }

  function claimText(Identifier memory identifier, Data memory data) public pure returns (bytes memory) {
    return abi.encodePacked(
      "Terminating VEGA market ",
      identifier.marketCode,
      " settled in ",
      identifier.quoteName,
      " enacted on ",
      identifier.enactmentDate,
      ", to terminate at ",
      Strings.toString(data.terminationTimestamp),
      address(identifier.conditionalSettlementOracle) == address(0)
        ? bytes("")
        : abi.encodePacked(
          " conditionally terminated by settlement oracle at ",
          Strings.toHexString(address(identifier.conditionalSettlementOracle))
        ),
      ".\n IPFS link to validation instructions: ",
      identifier.ipfsLink
    );
  }

  function id(Identifier calldata identifier) public view returns (bytes32) {
    return _id(abi.encode(identifier));
  }

  function getData(Identifier calldata identifier) public returns (bool, uint256, bool) {
    if (address(identifier.conditionalSettlementOracle) != address(0)) {
      SettlementOracle so2 = identifier.conditionalSettlementOracle;
      try so2.getData(_settlementIdentifier(identifier)) returns (bool hasResolved, uint256) {
        return (hasResolved, 0, hasResolved);
      } catch {}
    }

    Claim memory claim = _getClaim(id(identifier));
    bool result = _getAssertionResult(claim.assertionId);

    Data memory data = abi.decode(claim.data, (Data));

    return (result, data.terminationTimestamp, block.timestamp >= data.terminationTimestamp);
  }

  function getCachedData(Identifier calldata identifier) public view returns (bool, uint256, bool) {
    if (address(identifier.conditionalSettlementOracle) != address(0)) {
      SettlementOracle so2 = identifier.conditionalSettlementOracle;
      try so2.getCachedData(_settlementIdentifier(identifier)) returns (bool hasResolved, uint256) {
        return (hasResolved, 0, hasResolved);
      } catch {}
    }

    Claim memory claim = _getClaim(id(identifier));

    Data memory data = abi.decode(claim.data, (Data));

    return (claim.result, data.terminationTimestamp, block.timestamp >= data.terminationTimestamp);
  }

  function _settlementIdentifier(Identifier calldata identifier)
    internal
    pure
    returns (SettlementOracle.Identifier memory)
  {
    return SettlementOracle.Identifier({
      liveness: identifier.liveness,
      bondCurrency: identifier.bondCurrency,
      minimumBond: identifier.minimumBond,
      maximumBond: identifier.maximumBond,
      marketCode: identifier.marketCode,
      quoteName: identifier.quoteName,
      enactmentDate: identifier.enactmentDate,
      ipfsLink: identifier.ipfsLink
    });
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
      bytes32("ASSERT_TRUTH"),
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
