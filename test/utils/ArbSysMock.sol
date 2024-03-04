// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Copied from https://github.com/saucepoint/foundry-arbitrum/blob/1ff06d8dd25299851ec388e167c156396559892a/src/ArbSysMock.sol

/// @title ArbSysMock
/// @notice a mocked version of the Arbitrum system contract, add additional methods as needed
contract ArbSysMock {
  uint256 ticketId;

  function sendTxToL1(address _l1Target, bytes memory _data) external payable returns (uint256) {
    (bool success,) = _l1Target.call(_data);
    require(success, "Arbsys: sendTxToL1 failed");
    return ++ticketId;
  }
}
