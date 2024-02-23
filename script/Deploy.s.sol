// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SettlementOracle} from "../src/SettlementOracle.sol";
import {TerminationOracle} from "../src/TerminationOracle.sol";

interface IWETH {
  function deposit() external payable;
  function transfer(address, uint256) external returns (bool);
  function withdraw(uint256) external;
  function balanceOf(address) external view returns (uint256);
  function approve(address, uint256) external returns (bool);
}

contract DeployScript is Script {
  function setUp() public {}

  function run() public {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address owner = address(vm.addr(privateKey));

    address wethAddress = vm.envAddress("WETH_ADDRESS");
    require(wethAddress != address(0), "WETH address must be set");

    address oracleAddress = vm.envAddress("UMA_OPTIMISTIC_ORACLE_V3");
    require(oracleAddress != address(0), "Oracle address must be set");

    IWETH weth = IWETH(wethAddress);

    console.log("Address: %s", owner);
    console.log("Eth balance: %d", owner.balance);

    uint256 wethBalance = weth.balanceOf(owner);
    vm.startBroadcast(privateKey);

    if (wethBalance < 0.1 ether) {
      weth.deposit{value: 1 ether}();
    }

    SettlementOracle so = new SettlementOracle(oracleAddress, wethAddress);
    TerminationOracle to = new TerminationOracle(oracleAddress, wethAddress);

    weth.approve(address(so), 0.5 ether);
    weth.approve(address(to), 0.5 ether);

    vm.stopBroadcast();
  }
}
