// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { FarBarter } from "../src/FarBarter.sol";

contract Deploy is Script {
  FarBarter public farBarter;

  function setUp() public {}

  function run() public {
    vm.startBroadcast();

    farBarter = new FarBarter();
    console.log("FarBarter:", address(farBarter));

    vm.stopBroadcast();
  }
}
