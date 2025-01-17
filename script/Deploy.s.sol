// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { WeeklyHackathonWeekOneVotingTEST } from "../src/WeeklyHackathonWeekOneVotingTEST.sol";

contract Deploy is Script {
  WeeklyHackathonWeekOneVotingTEST public weeklyHackathonWeekOneVotingTEST;

  function setUp() public {}

  function run() public {
    vm.startBroadcast();

    weeklyHackathonWeekOneVotingTEST = new WeeklyHackathonWeekOneVotingTEST();
    console.log("WeeklyHackathonWeekOneVotingTEST:", address(weeklyHackathonWeekOneVotingTEST));

    vm.stopBroadcast();
  }
}
