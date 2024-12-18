// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
The Guest House - Rumi

This being human is a guest house.
Every morning a new arrival.

A joy, a depression, a meanness,
some momentary awareness comes
as an unexpected visitor.

Welcome and entertain them all!
Even if they're a crowd of sorrows,
who violently sweep your house
empty of its furniture,
still, treat each guest honorably.
He may be clearing you out
for some new delight.

The dark thought, the shame, the malice,
meet them at the door laughing,
and invite them in.

Be grateful for whoever comes,
because each has been sent
as a guide from beyond.
*/

import { ERC721 } from "solady/tokens/ERC721.sol";
import { LibString } from "solady/utils/LibString.sol";
import { Base64 } from "solady/utils/Base64.sol";

error Unauthorized();
error WritingSessionNotStarted();
error WritingSessionAlreadyEnded();
error WritingSessionTooLong();
error TryingToEndWrongSession(string sessionId, uint256 fid);
error SessionAlreadyMinted();
error SessionAlreadyStored();

contract AnkyFramesgiving is ERC721 {
  uint256 public constant WRITING_SESSION_DURATION = 8 minutes;

  address public immutable owner;

  // Token tracking
  uint256 private _tokenIdCounter;

  // Maps tokenId to IPFS hash containing metadata
  mapping(uint256 => string) private _tokenIPFSHashes;

  // Maps fid to their current writing session text
  mapping(uint256 => string) public currentWritingSession;

  // Maps fid to array of completed session IPFS hashes
  mapping(uint256 => string[]) public completedSessions;

  // Maps fid to array of anky IPFS hashes
  mapping(uint256 => mapping(string => bool)) public validUserAnkys;

  // Maps IPFS hash to whether it has been stored
  mapping(string => bool) public isHashStored;

  // Maps IPFS hash to whether it has been minted
  mapping(string => bool) public isHashMinted;

  // Maps fid to session start time
  mapping(uint256 => uint256[]) public sessionStartTimes;

  mapping(string => uint256) public sessionIdToTimestamp;

  // Maps fid to index in allWritersAtThisMoment for efficient removal
  mapping(uint256 => uint256) public writerToIndex;
  uint256[] public allWritersAtThisMoment;

  event SessionStarted(uint256 indexed fid, string indexed sessionId, uint256 indexed startTime);
  event SessionEndedAbruptly(uint256 indexed fid, string indexed sessionId);
  event SessionEnded(uint256 indexed fid, bool indexed isAnky, string indexed ipfsHash);
  event AnkyWritten(uint256 indexed fid, string indexed sessionId, string ipfsHash, uint256 writtenAt);
  event AnkyMinted(uint256 indexed fid, string ipfsHash, uint256 indexed tokenId);

  constructor() {
    owner = msg.sender;
    _tokenIdCounter = 0;
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
  }

  function name() public pure override returns (string memory) {
    return "Anky Framesgiving";
  }

  function symbol() public pure override returns (string memory) {
    return "ANKY";
  }

  function startSession(uint256 fid, string memory session_id) external onlyOwner {
    // If there's an open session, end it first
    require(bytes(session_id).length > 0, "Session ID cannot be empty");
    if (bytes(currentWritingSession[fid]).length > 0) {
      string memory openSessionId = currentWritingSession[fid];
      currentWritingSession[fid] = "";
      emit SessionEndedAbruptly(fid, openSessionId);
    }

    currentWritingSession[fid] = session_id;
    sessionStartTimes[fid].push(block.timestamp);
    sessionIdToTimestamp[session_id] = block.timestamp;
    writerToIndex[fid] = allWritersAtThisMoment.length;
    allWritersAtThisMoment.push(fid);
    emit SessionStarted(fid, session_id, block.timestamp);
  }

  function endSession(uint256 fid, string memory session_id, string memory ipfsHash, bool isAnky) public onlyOwner {
    if (bytes(currentWritingSession[fid]).length == 0) revert WritingSessionNotStarted();
    if (keccak256(bytes(currentWritingSession[fid])) != keccak256(bytes(session_id))) {
      revert TryingToEndWrongSession(session_id, fid);
    }

    // Check if hash has already been stored
    if (bytes(ipfsHash).length > 0) {
      if (isHashStored[ipfsHash]) revert SessionAlreadyStored();
      completedSessions[fid].push(ipfsHash);
      isHashStored[ipfsHash] = true;
    }

    // Remove writer from active writers - O(1) removal using index mapping
    if (allWritersAtThisMoment.length > 0) {
      uint256 indexToRemove = writerToIndex[fid];
      if (indexToRemove < allWritersAtThisMoment.length) {
        uint256 lastWriter = allWritersAtThisMoment[allWritersAtThisMoment.length - 1];
        allWritersAtThisMoment[indexToRemove] = lastWriter;
        writerToIndex[lastWriter] = indexToRemove;
        allWritersAtThisMoment.pop();
        delete writerToIndex[fid];
      }
    }

    currentWritingSession[fid] = "";

    if (isAnky && bytes(ipfsHash).length > 0) {
      validUserAnkys[fid][ipfsHash] = true;
      // Emit detailed event for Ponder indexing
      emit AnkyWritten(fid, session_id, ipfsHash, block.timestamp);
    }

    emit SessionEnded(fid, isAnky, ipfsHash);
  }

  function mintAnky(uint256 fid, address writerAddress, string memory writingIpfsHash, string memory metadataIpfsHash, string memory sessionId) external onlyOwner returns (uint256) {
    // Check if this ipfsHash exists in user's written Ankys
    require(validUserAnkys[fid][writingIpfsHash], "This Anky was not written by this address");

    // Check if hash has already been minted
    if (isHashMinted[writingIpfsHash]) revert SessionAlreadyMinted();

    // Check if enough time has elapsed since session start
    uint256 sessionStartTime = sessionIdToTimestamp[sessionId];
    require(block.timestamp >= sessionStartTime + WRITING_SESSION_DURATION, "Writing session duration not met");

    uint256 newTokenId = _tokenIdCounter++;
    _mint(writerAddress, newTokenId);

    // Store IPFS hash containing metadata
    _tokenIPFSHashes[newTokenId] = metadataIpfsHash;
    isHashMinted[writingIpfsHash] = true;

    emit AnkyMinted(fid, metadataIpfsHash, newTokenId);
    return newTokenId;
  }

  function getCompletedSessionCount(uint256 fid) external view returns (uint256) {
    return completedSessions[fid].length;
  }

  function getSessionStartTimes(uint256 fid) external view returns (uint256[] memory) {
    return sessionStartTimes[fid];
  }

  function getCurrentSession(uint256 fid) external view returns (string memory text) {
    return (currentWritingSession[fid]);
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    if (!_exists(tokenId)) revert("Token does not exist");
    return string(abi.encodePacked("ipfs://", _tokenIPFSHashes[tokenId]));
  }
}
