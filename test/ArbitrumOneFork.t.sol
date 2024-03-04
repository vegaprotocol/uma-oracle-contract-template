// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Test} from "forge-std/Test.sol";
import {ArbSysMock} from "./utils/ArbSysMock.sol";

import {BaseOracle, ClaimNotFound, ClaimAlreadySubmitted} from "../src/BaseOracle.sol";
import {SettlementOracle} from "../src/SettlementOracle.sol";
import {TerminationOracle} from "../src/TerminationOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

address constant ARBITRUM_OPTIMISTIC_ORACLE_V3 = 0xa6147867264374F324524E30C02C331cF28aa879;
address constant ARIBTRUM_BRIDGED_USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

contract ArbitrumOneTest is Test {
  SettlementOracle public settlementOracle;
  TerminationOracle public terminationOracle;

  IERC20 public USDC;

  SettlementOracle.Identifier public defaultSid;
  SettlementOracle.Data public defaultSd;

  TerminationOracle.Identifier public defaultTid;
  TerminationOracle.Data public defaultTd;

  function setUp() public {
    // Switch to built-in Arbitrum One fork
    Chain memory chain = getChain("arbitrum_one");
    uint256 forkId = vm.createFork(chain.rpcUrl);
    vm.selectFork(forkId);

    // Mock the ArbSys contract
    ArbSysMock arbsys = new ArbSysMock();
    vm.etch(address(0x0000000000000000000000000000000000000064), address(arbsys).code);

    settlementOracle = new SettlementOracle(ARBITRUM_OPTIMISTIC_ORACLE_V3);
    terminationOracle = new TerminationOracle(ARBITRUM_OPTIMISTIC_ORACLE_V3);
    USDC = IERC20(ARIBTRUM_BRIDGED_USDC);

    // Give test account 1000 USDC balance
    vm.prank(ARIBTRUM_BRIDGED_USDC);
    USDC.transfer(address(this), 2000e6);

    // Pre-approve USDC for settlementOracle and terminationOracle
    USDC.approve(address(settlementOracle), 1000e6);
    USDC.approve(address(terminationOracle), 1000e6);

    // Setup default settlement and termination identifiers to make tests more concise
    defaultSid = SettlementOracle.Identifier({
      liveness: 60 seconds,
      bondCurrency: USDC,
      minimumBond: 500e6,
      maximumBond: 1000e6,
      marketCode: "BTC-USD",
      quoteName: "USD",
      enactmentDate: "2022-01-01",
      ipfsLink: "ipfs://QmXZz"
    });

    defaultSd = SettlementOracle.Data({price: 1000});

    defaultTid = TerminationOracle.Identifier({
      liveness: defaultSid.liveness,
      bondCurrency: defaultSid.bondCurrency,
      minimumBond: defaultSid.minimumBond,
      maximumBond: defaultSid.maximumBond,
      marketCode: defaultSid.marketCode,
      quoteName: defaultSid.quoteName,
      enactmentDate: defaultSid.enactmentDate,
      ipfsLink: defaultSid.ipfsLink,
      conditionalSettlementOracle: settlementOracle
    });

    defaultTd = TerminationOracle.Data({terminationTimestamp: block.timestamp + 1 hours});
  }

  function test_settlementWithFinalize() public {
    assertUnknownSettlement();

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertPreSettlement();

    assertSettlementSubmitted();

    skip(defaultSid.liveness + 1 seconds);

    {
      (bool resolvedCached, uint256 priceCached) = settlementOracle.getCachedData(defaultSid);
      assertFalse(resolvedCached, "Cached data should not be resolved yet");
      assertEq(priceCached, defaultSd.price);
    }

    settlementOracle.finalizeClaim(defaultSid);

    assertPostSettlement();
  }

  function test_settlementWithGetData() public {
    assertUnknownSettlement();

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertPreSettlement();

    assertSettlementSubmitted();

    skip(defaultSid.liveness + 1 seconds);

    {
      (bool resolved, uint256 price) = settlementOracle.getCachedData(defaultSid);
      assertFalse(resolved, "Cached data should not be resolved yet");
      assertEq(price, defaultSd.price);
    }

    // Trigger settlement
    {
      (bool resolved, uint256 price) = settlementOracle.getData(defaultSid);
      assertTrue(resolved, "Data should be resolved");
      assertEq(price, defaultSd.price);
    }

    assertPostSettlement();
  }

  function test_terminationWithFinalize() public {
    assertUnknownTermination();

    terminationOracle.submitClaim(defaultTid, defaultTd);

    assertPreTermination();
    assertTerminationSubmitted();

    skip(defaultTid.liveness + 1 seconds);

    {
      (bool resolved, uint256 ts, bool terminated) = terminationOracle.getCachedData(defaultTid);
      assertFalse(resolved, "Cached data should not be resolved yet");
      assertEq(ts, defaultTd.terminationTimestamp);
      assertFalse(terminated);
    }

    terminationOracle.finalizeClaim(defaultTid);

    assertPostTermination();

    vm.warp(defaultTd.terminationTimestamp + 1 seconds);

    assertTerminated();
  }

  function test_terminationWithGetData() public {
    assertUnknownTermination();

    terminationOracle.submitClaim(defaultTid, defaultTd);

    assertPreTermination();
    assertTerminationSubmitted();

    skip(defaultTid.liveness + 1 seconds);

    {
      (bool resolved, uint256 ts, bool terminated) = terminationOracle.getCachedData(defaultTid);
      assertFalse(resolved, "Cached data should not be resolved yet");
      assertEq(ts, defaultTd.terminationTimestamp);
      assertFalse(terminated);
    }

    // Trigger termination
    {
      (bool resolved, uint256 ts, bool terminated) = terminationOracle.getData(defaultTid);
      assertTrue(resolved, "Data should be resolved");
      assertEq(ts, defaultTd.terminationTimestamp);
      assertFalse(terminated);
    }

    assertPostTermination();

    vm.warp(defaultTd.terminationTimestamp + 1 seconds);

    assertTerminated();
  }

  function test_terminationViaSettlement() public {
    assertUnknownTermination();
    assertUnknownSettlement();

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertPreSettlement();
    assertSettlementSubmitted();

    assertPreTerminationViaSettlement();

    skip(defaultSid.liveness + 1 seconds);
    settlementOracle.finalizeClaim(defaultSid);

    assertPostSettlement();

    assertTerminated();
  }

  function test_terminationWithoutSettlementOracle() public {
    TerminationOracle.Identifier memory tid = TerminationOracle.Identifier({
      liveness: defaultSid.liveness,
      bondCurrency: defaultSid.bondCurrency,
      minimumBond: defaultSid.minimumBond,
      maximumBond: defaultSid.maximumBond,
      marketCode: defaultSid.marketCode,
      quoteName: defaultSid.quoteName,
      enactmentDate: defaultSid.enactmentDate,
      ipfsLink: defaultSid.ipfsLink,
      conditionalSettlementOracle: SettlementOracle(address(0))
    });

    assertUnknownTermination(tid);
    assertUnknownSettlement();

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertUnknownTermination(tid);

    skip(defaultSid.liveness + 1 seconds);

    settlementOracle.finalizeClaim(defaultSid);

    assertUnknownTermination(tid);

    assertPostSettlement();

    terminationOracle.submitClaim(tid, defaultTd);

    assertPreTermination(tid, defaultTd);

    skip(tid.liveness + 1 seconds);

    terminationOracle.finalizeClaim(tid);

    assertPostTermination(tid, defaultTd);

    vm.warp(defaultTd.terminationTimestamp + 1 seconds);

    assertTerminated(tid);
  }

  function test_terminationOverriddenBySettlement() public {
    assertUnknownTermination();
    assertUnknownSettlement();

    terminationOracle.submitClaim(defaultTid, defaultTd);

    assertPreTermination();

    assertTerminationSubmitted();
    assertUnknownSettlement();

    skip(defaultTid.liveness / 2);

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertPreSettlement();
    assertSettlementSubmitted();

    assertPreTerminationViaSettlement();

    skip(defaultTid.liveness / 2 + 1 seconds);

    assertPreSettlement();
    assertPreTerminationViaSettlement();

    skip(defaultTid.liveness / 2);

    settlementOracle.finalizeClaim(defaultSid);

    assertPostSettlement();
    assertTerminated();
  }

  function test_disputedSettlement() public {
    assertUnknownSettlement();

    settlementOracle.submitClaim(defaultSid, defaultSd);

    assertPreSettlement();

    assertSettlementSubmitted();

    skip(defaultSid.liveness / 2);

    bytes32 assertionId = getAssertionId(defaultSid);

    USDC.approve(address(settlementOracle.oracle()), 1000e6);
    settlementOracle.oracle().disputeAssertion(assertionId, address(this));

    assertUnknownSettlement();
  }

  function assertUnknownSettlement() internal {
    assertUnknownSettlement(settlementOracle, defaultSid);
  }

  function assertUnknwonSettlement(SettlementOracle.Identifier memory sid) internal {
    assertUnknownSettlement(settlementOracle, sid);
  }

  function assertUnknownSettlement(SettlementOracle _settlementOracle, SettlementOracle.Identifier memory sid) internal {
    vm.expectRevert(abi.encodeWithSelector(ClaimNotFound.selector));
    _settlementOracle.getData(sid);
  }

  function assertSettlementSubmitted() internal {
    assertSettlementSubmitted(settlementOracle, defaultSid);
  }

  function assertSettlementSubmitted(SettlementOracle.Identifier memory sid) internal {
    assertSettlementSubmitted(settlementOracle, sid);
  }

  function assertSettlementSubmitted(SettlementOracle _settlementOracle, SettlementOracle.Identifier memory sid)
    internal
  {
    bytes32 assertionId = getAssertionId(_settlementOracle, sid);
    vm.expectRevert(abi.encodeWithSelector(ClaimAlreadySubmitted.selector, assertionId));
    settlementOracle.submitClaim(sid, SettlementOracle.Data({price: 1000}));
  }

  function assertPreSettlement() internal {
    assertPreSettlement(settlementOracle, defaultSid, defaultSd);
  }

  function assertPreSettlement(SettlementOracle.Identifier memory sid, SettlementOracle.Data memory sd) internal {
    assertPreSettlement(settlementOracle, sid, sd);
  }

  function assertPreSettlement(
    SettlementOracle _settlementOracle,
    SettlementOracle.Identifier memory sid,
    SettlementOracle.Data memory sd
  ) internal {
    (bool resolvedCached, uint256 priceCached) = _settlementOracle.getCachedData(sid);
    assertFalse(resolvedCached);
    assertEq(priceCached, sd.price);

    (bool resolved, uint256 price) = _settlementOracle.getData(sid);
    assertFalse(resolved);
    assertEq(price, sd.price);
  }

  function assertPostSettlement() internal {
    assertPostSettlement(settlementOracle, defaultSid, defaultSd);
  }

  function assertPostSettlement(SettlementOracle.Identifier memory sid, SettlementOracle.Data memory sd) internal {
    assertPostSettlement(settlementOracle, sid, sd);
  }

  function assertPostSettlement(
    SettlementOracle _settlementOracle,
    SettlementOracle.Identifier memory sid,
    SettlementOracle.Data memory sd
  ) internal {
    (bool resolvedCached, uint256 priceCached) = _settlementOracle.getCachedData(sid);
    assertTrue(resolvedCached);
    assertEq(priceCached, sd.price);

    (bool resolved, uint256 price) = _settlementOracle.getData(sid);
    assertTrue(resolved);
    assertEq(price, sd.price);
  }

  function assertUnknownTermination() internal {
    assertUnknownTermination(terminationOracle, defaultTid);
  }

  function assertUnknownTermination(TerminationOracle.Identifier memory tid) internal {
    assertUnknownTermination(terminationOracle, tid);
  }

  function assertUnknownTermination(TerminationOracle _terminationOracle, TerminationOracle.Identifier memory tid)
    internal
  {
    vm.expectRevert(abi.encodeWithSelector(ClaimNotFound.selector));
    _terminationOracle.getData(tid);
  }

  function assertTerminationSubmitted() internal {
    assertTerminationSubmitted(terminationOracle, defaultTid);
  }

  function assertTerminationSubmitted(TerminationOracle.Identifier memory tid) internal {
    assertTerminationSubmitted(terminationOracle, tid);
  }

  function getAssertionId(SettlementOracle.Identifier memory sid) internal view returns (bytes32) {
    return getAssertionId(settlementOracle, sid);
  }

  function getAssertionId(SettlementOracle _settlementOracle, SettlementOracle.Identifier memory sid)
    internal
    view
    returns (bytes32 assertionId)
  {
    (assertionId,,) = _settlementOracle.claims(_settlementOracle.id(sid));
  }

  function getAssertionId(TerminationOracle.Identifier memory tid) internal view returns (bytes32) {
    return getAssertionId(terminationOracle, tid);
  }

  function getAssertionId(TerminationOracle _terminationOracle, TerminationOracle.Identifier memory tid)
    internal
    view
    returns (bytes32 assertionId)
  {
    (assertionId,,) = _terminationOracle.claims(_terminationOracle.id(tid));
  }

  function assertTerminationSubmitted(TerminationOracle _terminationOracle, TerminationOracle.Identifier memory tid)
    internal
  {
    bytes32 assertionId = getAssertionId(_terminationOracle, tid);
    vm.expectRevert(abi.encodeWithSelector(ClaimAlreadySubmitted.selector, assertionId));
    terminationOracle.submitClaim(tid, TerminationOracle.Data({terminationTimestamp: 0}));
  }

  function assertPreTermination() internal {
    assertPreTermination(terminationOracle, defaultTid, defaultTd);
  }

  function assertPreTermination(TerminationOracle.Identifier memory tid, TerminationOracle.Data memory td) internal {
    assertPreTermination(terminationOracle, tid, td);
  }

  function assertPreTermination(
    TerminationOracle _terminationOracle,
    TerminationOracle.Identifier memory tid,
    TerminationOracle.Data memory td
  ) internal {
    (bool resolvedCached, uint256 tsCached, bool terminatedCached) = _terminationOracle.getCachedData(tid);
    assertFalse(resolvedCached);
    assertEq(tsCached, td.terminationTimestamp);
    assertFalse(terminatedCached);

    (bool resolved, uint256 ts, bool terminated) = _terminationOracle.getData(tid);
    assertFalse(resolved);
    assertEq(ts, td.terminationTimestamp);
    assertFalse(terminated);
  }

  function assertPreTerminationViaSettlement() internal {
    assertPreTerminationViaSettlement(terminationOracle, defaultTid);
  }

  function assertPreTerminationViaSettlement(TerminationOracle.Identifier memory tid) internal {
    assertPreTerminationViaSettlement(terminationOracle, tid);
  }

  function assertPreTerminationViaSettlement(
    TerminationOracle _terminationOracle,
    TerminationOracle.Identifier memory tid
  ) internal {
    (bool resolvedCached, uint256 tsCached, bool terminatedCached) = _terminationOracle.getCachedData(tid);
    assertFalse(resolvedCached);
    assertEq(tsCached, 0);
    assertFalse(terminatedCached);

    (bool resolved, uint256 ts, bool terminated) = _terminationOracle.getData(tid);
    assertFalse(resolved);
    assertEq(ts, 0);
    assertFalse(terminated);
  }

  function assertPostTermination() internal {
    assertPostTermination(terminationOracle, defaultTid, defaultTd);
  }

  function assertPostTermination(TerminationOracle.Identifier memory tid, TerminationOracle.Data memory td) internal {
    assertPostTermination(terminationOracle, tid, td);
  }

  function assertPostTermination(
    TerminationOracle _terminationOracle,
    TerminationOracle.Identifier memory tid,
    TerminationOracle.Data memory td
  ) internal {
    (bool resolvedCached, uint256 tsCached, bool terminatedCached) = _terminationOracle.getCachedData(tid);
    assertTrue(resolvedCached);
    assertEq(tsCached, td.terminationTimestamp);
    assertFalse(terminatedCached);

    (bool resolved, uint256 ts, bool terminated) = _terminationOracle.getData(tid);
    assertTrue(resolved);
    assertEq(ts, td.terminationTimestamp);
    assertFalse(terminated);
  }

  function assertTerminated() internal {
    assertTerminated(terminationOracle, defaultTid);
  }

  function assertTerminated(TerminationOracle.Identifier memory tid) internal {
    assertTerminated(terminationOracle, tid);
  }

  function assertTerminated(TerminationOracle _terminationOracle, TerminationOracle.Identifier memory tid) internal {
    (bool resolvedCached,, bool terminatedCached) = _terminationOracle.getCachedData(tid);
    assertTrue(resolvedCached);
    assertTrue(terminatedCached);

    (bool resolved,, bool terminated) = _terminationOracle.getData(tid);
    assertTrue(resolved);
    assertTrue(terminated);
  }
}
