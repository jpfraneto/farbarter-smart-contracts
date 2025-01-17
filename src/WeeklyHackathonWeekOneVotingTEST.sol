// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC721 } from "solady/tokens/ERC721.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WeeklyHackathonWeekOneVotingTEST is ERC721 {
  using LibString for uint256;

  address public owner;
  uint256 private _tokenIdCounter;

  // Hackathon token contract
  IERC20 public constant HACKATHON_TOKEN = IERC20(0x3dF58A5737130FdC180D360dDd3EFBa34e5801cb);
  uint256 public constant MIN_TOKENS_TO_VOTE = 88888 * 1e18; // 88,888 tokens with 18 decimals

  // Mapping to track whitelisted voters
  mapping(address => bool) public isWhitelisted;
  mapping(address => uint256) public voterFids;
  mapping(uint256 => string) private _tokenIPFSHashes;
  mapping(address => bool) public hasVoted;

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  event VoterWhitelisted(address indexed voter, uint256 fid);
  event VoteCast(address indexed voter, string voteString, string metadataIpfsHash);

  constructor() {
    owner = msg.sender;
    _tokenIdCounter = 0;
  }

  function name() public pure override returns (string memory) {
    return "weeklyHackathon week-1 voting TEST";
  }

  function symbol() public pure override returns (string memory) {
    return "WHWOV";
  }

  // Owner function to whitelist voters
  function whitelistVoter(address voter, uint256 fid) external onlyOwner {
    require(voter != address(0), "Invalid voter address");
    require(fid > 0, "Invalid FID");
    require(!isWhitelisted[voter], "Voter already whitelisted");

    isWhitelisted[voter] = true;
    voterFids[voter] = fid;

    emit VoterWhitelisted(voter, fid);
  }

  // Function to cast vote
  function castVote(string calldata voteString, string calldata metadataIpfsHash) external {
    require(isWhitelisted[msg.sender], "Voter not whitelisted");
    require(!hasVoted[msg.sender], "Already voted");
    require(HACKATHON_TOKEN.balanceOf(msg.sender) >= MIN_TOKENS_TO_VOTE, "Insufficient $HACKATHON tokens");

    _tokenIdCounter++;
    uint256 tokenId = _tokenIdCounter;
    _mint(msg.sender, tokenId);
    _tokenIPFSHashes[tokenId] = metadataIpfsHash;

    hasVoted[msg.sender] = true;

    emit VoteCast(msg.sender, voteString, metadataIpfsHash);
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    if (!_exists(tokenId)) revert("Token does not exist");
    return string(abi.encodePacked("ipfs://", _tokenIPFSHashes[tokenId]));
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "New owner cannot be zero address");
    owner = newOwner;
  }
}
