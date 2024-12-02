// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Yoink, Score} from "../src/Yoink.sol";

contract GenerateTokenArt is Script {
    function setUp() public {}

    function run() public {
        address testAddress = address(0x1234567890123456789012345678901234567890);
        Score memory testScore =
            Score({yoinks: 4200000, time: 43200000, lastYoinkedAt: block.timestamp});

        Yoink yoink = new Yoink();

        string memory flagSVG = yoink.generateFlagSVG(testAddress, testScore);
        string memory flagJSON = yoink.generateFlagJSON(testAddress, testScore);

        string memory trophySVG = yoink.generateTrophySVG(testAddress, testScore);
        string memory trophyJSON = yoink.generateTrophyJSON(testAddress, testScore);

        string memory scoreSVG = yoink.generateScoreSVG(testAddress, testScore);
        string memory scoreJSON = yoink.generateScoreJSON(testAddress, testScore);

        vm.writeFile("./tmp/flag.svg", flagSVG);
        vm.writeFile("./tmp/flag.json", flagJSON);
        vm.writeFile("./tmp/trophy.svg", trophySVG);
        vm.writeFile("./tmp/trophy.json", trophyJSON);
        vm.writeFile("./tmp/score.svg", scoreSVG);
        vm.writeFile("./tmp/score.json", scoreJSON);
    }
}
