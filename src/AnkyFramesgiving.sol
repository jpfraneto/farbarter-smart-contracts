// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
AnkyFramesgiving: A Revolutionary Writing Experience on Ethereum

This contract creates a unique intersection of creative expression and blockchain technology.
It gamifies the writing process through time-boxed sessions while ensuring fair participation
and rewarding authentic creative engagement. The 8-minute writing sessions create a
"proof of creative work" mechanism, turning ephemeral moments of inspiration into
permanent digital artifacts.
*/

import {ERC721} from "solady/tokens/ERC721.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

// TODO: Create interfaces for token factories:
// IClankerTokenFactory should have:
// - function deployToken(string name, string symbol, uint256 supply) returns (address)

// IJerryTokenFactory should have:
// - function deployToken(string name, string symbol, uint256 supply) returns (address)

error MintingPeriodEnded();
error AnkyAlreadyRevealed();
error Unauthorized();
error InvalidTokenId();
error NotApprovedForMinting();
error TokenNotAssigned();
error WritingSessionNotStarted();
error WritingSessionTooRecent();
error WritingSessionNotEnded();
error ActiveSessionExists();
error WritingSessionAlreadyEnded();
error WritingSessionTooLong();
error InvalidTimestamp();
error InvalidTokenProvider();
error TokenAlreadyDeployed();

contract AnkyFramesgiving is ERC721 {
    uint256 public constant MINTING_PERIOD = 24 hours;
    uint256 public constant WRITING_SESSION_DURATION = 8 minutes;
    uint256 public constant REFERENCE_TIMESTAMP = 1691658000;
    uint256 public constant DAY_DURATION = 24 hours;
    uint256 public constant MAX_SESSION_LENGTH = 10 minutes;
    
    address public immutable owner;
    ERC20 public immutable newenToken;
    address public immutable clankerFactory;
    address public immutable jerryFactory;
    
    struct TokenMetadata {
        bytes32 writingHash;
        string imageURI;
        bool ankyRevealed;
        uint256 mintingStartedAt;
        uint256 writingSessionStartedAt;
        bytes32 writingSessionId;
        bytes32 metadata;
    }

    struct WritingSession {
        int userFid;
        address userWallet;
        bytes32 writingSessionId;
        uint256 startingTimestamp;
        uint256 endedTimestamp;
        bytes32 ipfsHash;
        bool isAnky;
        address deployedToken;
    }
    
    mapping(uint256 => TokenMetadata) public tokenMetadata;
    mapping(address => bool) public approvedMinters;
    mapping(int => bytes32[]) public writingSessionsToUsers;
    mapping(bytes32 => WritingSession) public writingSessions;
    uint256 public totalSupply;
    
    event WritingSessionStarted(int indexed userFid, bytes32 indexed writingSessionId, uint256 startingTimestamp);
    event WritingSessionCompleted(int indexed userFid, bytes32 indexed writingSessionId, uint256 endingTimestamp, bytes32 metadata);
    event AnkyMinted(address indexed recipient, bytes32 writingHash, uint256 tokenId);
    event TokenDeployed(bytes32 indexed writingSessionId, address indexed tokenAddress);
    
    constructor(
        address _newenToken
    ) {
        owner = msg.sender;
        newenToken = ERC20(_newenToken);
    }

    function name() public pure virtual override returns (string memory) {
        return "Anky Framesgiving";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "ANKY";
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier validTimestamp(uint256 timestamp) {
        if (timestamp > block.timestamp) revert InvalidTimestamp();
        _;
    }

    function checkIfUserHasActiveSession(int userFid) public view returns (bytes32) {
        bytes32[] memory userSessions = writingSessionsToUsers[userFid];
        for (uint i = 0; i < userSessions.length; i++) {
            WritingSession memory session = writingSessions[userSessions[i]];
            if (session.endedTimestamp == 0) {
                return session.writingSessionId;
            }
        }
        return bytes32(0);
    }

    function getCurrentDay() public view returns (uint256) {
        if (block.timestamp < REFERENCE_TIMESTAMP) return 0;
        return (block.timestamp - REFERENCE_TIMESTAMP) / DAY_DURATION;
    }

    function startNewWritingSession(
        int userFid, 
        bytes32 writing_session_id, 
        address userWallet
    ) external onlyOwner {
        if (checkIfUserHasActiveSession(userFid) != bytes32(0)) revert ActiveSessionExists();

        writingSessionsToUsers[userFid].push(writing_session_id);
        writingSessions[writing_session_id] = WritingSession({
            userFid: userFid,
            writingSessionId: writing_session_id,
            startingTimestamp: block.timestamp,
            endedTimestamp: 0,
            userWallet: userWallet,
            isAnky: false,
            ipfsHash: bytes32(0),
            deployedToken: address(0)
        });
        
        emit WritingSessionStarted(userFid, writing_session_id, block.timestamp);
    }

    function endWritingSession(
        int userFid, 
        bytes32 writing_session_id, 
        bytes32 ipfs_hash
    ) external validTimestamp(block.timestamp) onlyOwner {
        WritingSession storage session = writingSessions[writing_session_id];
        
        if (session.userFid != userFid) revert Unauthorized();   
        if (session.endedTimestamp != 0) revert WritingSessionAlreadyEnded();
        if (session.startingTimestamp == 0) revert WritingSessionNotStarted();
        
        uint256 sessionDuration = block.timestamp - session.startingTimestamp;
        if (sessionDuration > MAX_SESSION_LENGTH) revert WritingSessionTooLong();
        
        session.isAnky = sessionDuration > WRITING_SESSION_DURATION;
        session.ipfsHash = ipfs_hash;
        session.endedTimestamp = block.timestamp;
        
        emit WritingSessionCompleted(userFid, writing_session_id, block.timestamp, ipfs_hash);
    }

    function deployAnky(
        bytes32 writing_session_id, 
        string memory tokenSymbol, 
        string memory tokenName, 
        uint256 tokenSupply, 
        string memory tokenProvider
    ) public {
        WritingSession storage session = writingSessions[writing_session_id];
        if (msg.sender != session.userWallet) revert Unauthorized();
        if (!session.isAnky) revert WritingSessionTooRecent();
        if (session.endedTimestamp == 0) revert WritingSessionNotEnded();
        if (session.deployedToken != address(0)) revert TokenAlreadyDeployed();

        // TODO: Implement actual token deployment once interfaces are created
        address deployedToken;
        if (keccak256(abi.encodePacked(tokenProvider)) == keccak256(abi.encodePacked("jerry"))) {
            // Will call: deployedToken = IJerryTokenFactory(jerryFactory).deployToken(tokenName, tokenSymbol, tokenSupply);
            deployedToken = address(0);
        } else if (keccak256(abi.encodePacked(tokenProvider)) == keccak256(abi.encodePacked("clanker"))) {
            // Will call: deployedToken = IClankerTokenFactory(clankerFactory).deployToken(tokenName, tokenSymbol, tokenSupply);
            deployedToken = address(0);
        } else {
            revert InvalidTokenProvider();
        }

        session.deployedToken = deployedToken;
        emit TokenDeployed(writing_session_id, deployedToken);

        uint256 tokenId = totalSupply + 1;
        _mint(session.userWallet, tokenId);
        totalSupply = tokenId;

        tokenMetadata[tokenId] = TokenMetadata({
            writingHash: session.ipfsHash,
            imageURI: "",
            ankyRevealed: false,
            mintingStartedAt: block.timestamp,
            writingSessionStartedAt: session.startingTimestamp,
            writingSessionId: writing_session_id,
            metadata: bytes32(0)
        });

        emit AnkyMinted(session.userWallet, session.ipfsHash, tokenId);
    }
 
    function withdrawNewen() external onlyOwner {
        uint256 balance = newenToken.balanceOf(address(this));
        bool success = newenToken.transfer(owner, balance);
        require(success, "Token transfer failed");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return tokenMetadata[tokenId].imageURI;
    }
}
