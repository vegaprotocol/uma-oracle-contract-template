// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {OptimisticOracleV3Interface} from
  "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

error ClaimNotFound();
error ClaimAlreadySubmitted(bytes32 assertionId);
error Unauthorized();
error BondOutOfRange(uint256 minimumBond, uint256 maximumBond, uint256 bond);

contract BaseOracle {
  /// @dev `Claim` contains a OOv3 `assertionId`, the result of the claim and any additional data provided by child contracts.
  /// @param assertionId The identifier of the assertion provided by OOv3
  /// @param data Additional data provided by child contracts. Can be stored with `abi.encode()` and decoded with `abi.decode(claim.data, (TYPE))`.
  /// @param result The result of the claim. Will be `false` by default, but resolve to `true` if the claim is accepted.
  struct Claim {
    bytes32 assertionId;
    bytes data;
    bool result;
  }

  /// @dev Emitted when a claim is submitted to OOv3.
  /// @param claimId The identifier of the claim as returned by `id()`.
  /// @param assertionId The identifier of the assertion as returned by OOv3.
  event Submitted(bytes32 indexed claimId, bytes32 indexed assertionId);
  /// @dev Emitted when a claim is resolved by OOv3.
  /// @param result The result of the claim. Will be `true` if the claim is accepted, `false` if it is rejected.
  /// @param claimId The identifier of the claim as returned by `id()`.
  /// @param assertionId The identifier of the assertion as returned by OOv3.
  event Resolved(bool result, bytes32 indexed claimId, bytes32 indexed assertionId);
  /// @dev Emitted when a claim is disputed by OOv3. This does not necessarily mean the claim is rejected.
  /// @param claimId The identifier of the claim as returned by `id()`.
  /// @param assertionId The identifier of the assertion as returned by OOv3.
  event Disputed(bytes32 indexed claimId, bytes32 indexed assertionId);

  mapping(bytes32 => Claim) public claims;
  mapping(bytes32 => bytes32) public assertionToClaimId;

  OptimisticOracleV3Interface public immutable oracle;

  constructor(address _oracle) {
    oracle = OptimisticOracleV3Interface(_oracle);
  }

  modifier onlyOracle() {
    if (msg.sender != address(oracle)) {
      revert Unauthorized();
    }

    _;
  }

  /**
   * @dev Helper function to settle an assertion and release the bond.
   * @dev It is cheaper to settle the assertion directly with the OOv3 contract than to call this function, however this provides the convenience of accepting a claimId and resolving it to the correct assertion.
   * @param claimId The identifier of the claim to finalize.
   */
  function _finalizeClaim(bytes32 claimId) internal {
    bytes32 assertionId = claims[claimId].assertionId;

    if (assertionId == 0) {
      revert ClaimNotFound();
    }
    oracle.settleAssertion(assertionId);
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved.
   * @param assertionId The identifier of the assertion that was resolved.
   * @param result The result of the assertion.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool result) external onlyOracle {
    bytes32 claimId = assertionToClaimId[assertionId];
    if (claimId == 0) {
      return;
    }

    if (result) {
      claims[claimId].result = true;
      emit Resolved(true, claimId, assertionId);
    } else {
      delete claims[claimId];
      delete assertionToClaimId[assertionId];
      emit Resolved(false, claimId, assertionId);
    }
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is disputed.
   * @param assertionId The identifier of the assertion that was disputed.
   */
  function assertionDisputedCallback(bytes32 assertionId) external onlyOracle {
    bytes32 claimId = assertionToClaimId[assertionId];
    if (claimId == 0) {
      return;
    }

    delete claims[claimId];
    delete assertionToClaimId[assertionId];

    emit Disputed(claimId, assertionId);
  }

  /// @dev Internal id helper function.
  function _id(bytes memory entropy) internal view returns (bytes32) {
    return keccak256(abi.encode(block.chainid, address(this), entropy));
  }

  function _getClaim(bytes32 claimId) internal view returns (Claim memory) {
    Claim memory claim = claims[claimId];
    if (claim.assertionId == 0) {
      revert ClaimNotFound();
    }

    return claim;
  }

  function _getAssertionResult(bytes32 assertionId) internal returns (bool) {
    try oracle.settleAndGetAssertionResult(assertionId) returns (bool result) {
      return result;
    } catch {
      return false;
    }
  }
}
