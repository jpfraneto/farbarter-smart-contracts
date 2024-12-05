// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AnkyFramesgiving} from "../src/AnkyFramesgiving.sol";

contract Deploy is Script {
    AnkyFramesgiving public ankyFramesgiving;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ankyFramesgiving = new AnkyFramesgiving(0xffe3CDC92F24988Be4f6F8c926758dcE490fe77E);
        console.log("AnkyFramesgiving:", address(ankyFramesgiving));

        vm.stopBroadcast();
    }
}
