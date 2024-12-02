// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

/*
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
- Rumi, The Guest House
*/

// Custom errors for better gas efficiency and clarity
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
error AlreadyMinted();

// Event emitted when a new writing session begins
event WritingSessionStarted(int indexed userFid, string indexed writingSessionId, uint256 startingTimestamp);
// Event emitted when a writing session is completed successfully
event WritingSessionCompleted(int indexed userFid, string indexed writingSessionId, uint256 endingTimestamp);
// Event emitted when an Anky token is minted
event AnkyMinted(address indexed recipient, string writingHash);

contract AnkyFramesgiving is ERC721 {
    // Constants for timing requirements
    uint256 public constant MINTING_PERIOD = 24 hours;
    uint256 public constant WRITING_SESSION_DURATION = 8 minutes;
    
    address public immutable owner;
    
    // Metadata structure for the NFT
    struct TokenMetadata {
        string writingHash;          // Hash of the writing content
        string imageURI;            // URI of the revealed Anky image
        bool ankyRevealed;          // Whether the Anky has been revealed
        uint256 mintingStartedAt;   // Timestamp when minting period began
        uint256 writingSessionStartedAt; // Timestamp of writing session start
        string writingSessionId;    // ID of the associated writing session
    }

    // Structure to track individual writing sessions
    struct WritingSession {
        int userFid;               // User's Farcaster ID
        string writingSessionId;   // Unique session identifier
        uint256 startingTimestamp; // When the session began
        bool ended;                // Whether session has concluded
        address userWallet;        // User's wallet address
        bool isAnky;              // Whether session qualified for Anky
    }
    
    TokenMetadata public tokenMetadata;
    mapping(address => bool) public approvedMinters;
    mapping(int => string[]) public writingSessionsToUsers;
    mapping(string => WritingSession) public writingSessions;
    bool public minted;
    
    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // Checks if a user has an ongoing writing session
    function checkIfUserHasActiveSession(int userFid) public view returns (string memory) {
        if (writingSessionsToUsers[userFid].length == 0) {
            return "";
        }

        string memory latestSessionId = writingSessionsToUsers[userFid][writingSessionsToUsers[userFid].length - 1];
        WritingSession memory latestSession = writingSessions[latestSessionId];

        if (latestSession.startingTimestamp != 0 && 
            latestSession.startingTimestamp + WRITING_SESSION_DURATION > block.timestamp) {
            return latestSessionId;
        }

        return "";
    }

    // Initiates a new writing session for a user
    function startNewWritingSession(int userFid, string calldata writing_session_id, address userWallet) external onlyOwner {
        string memory activeSession = checkIfUserHasActiveSession(userFid);
        if (bytes(activeSession).length > 0) {
            revert ActiveSessionExists();
        }

        writingSessionsToUsers[userFid].push(writing_session_id);
        writingSessions[writing_session_id] = WritingSession({
            userFid: userFid,
            writingSessionId: writing_session_id,
            startingTimestamp: block.timestamp,
            ended: false,
            userWallet: userWallet,
            isAnky: false
        });
        
        // Update token metadata for potential minting
        tokenMetadata.writingSessionStartedAt = block.timestamp;
        tokenMetadata.writingSessionId = writing_session_id;
        
        emit WritingSessionStarted(userFid, writing_session_id, block.timestamp);
    }

    // Concludes a writing session and handles rewards
    function endWritingSession(int userFid, string calldata writing_session_id) external {
        if(writingSessions[writing_session_id].userFid != userFid) revert Unauthorized();   
        if(writingSessions[writing_session_id].ended) revert WritingSessionAlreadyEnded();
        
        WritingSession storage session = writingSessions[writing_session_id];
        
        if(block.timestamp > session.startingTimestamp + WRITING_SESSION_DURATION) {
            // Full session completed - approve for minting
            if(session.userWallet != msg.sender) revert Unauthorized();
            session.isAnky = true;
            approvedMinters[msg.sender] = true;
            emit WritingSessionCompleted(userFid, writing_session_id, block.timestamp);
            closeSession(writing_session_id);
        } else {
            // Early termination
            if(msg.sender != owner) revert Unauthorized();
            closeSession(writing_session_id);
        }
    }

    // Internal function to mark session as ended
    function closeSession(string calldata writing_session_id) internal {
        writingSessions[writing_session_id].ended = true;
    }

    // Mints an Anky token for completed writing sessions
    function mint(string calldata writingHash) external {
        if (!approvedMinters[msg.sender]) revert NotApprovedForMinting();
        if (minted) revert AlreadyMinted();
        
        if (tokenMetadata.writingSessionStartedAt == 0) revert WritingSessionNotStarted();
        
        if (block.timestamp < tokenMetadata.writingSessionStartedAt + WRITING_SESSION_DURATION) {
            revert WritingSessionTooRecent();
        }
        
        if (tokenMetadata.mintingStartedAt == 0) {
            tokenMetadata.mintingStartedAt = block.timestamp;
        }
        
        if (block.timestamp > tokenMetadata.mintingStartedAt + MINTING_PERIOD) {
            revert MintingPeriodEnded();
        }

        _mint(msg.sender, 1);
        tokenMetadata.writingHash = writingHash;
        approvedMinters[msg.sender] = false;
        minted = true;
        
        emit AnkyMinted(msg.sender, writingHash);
    }

    // Allows owner to reveal the Anky artwork
    function revealAnky(string calldata imageURI) external onlyOwner {
        if (!minted) revert InvalidTokenId();
        if (tokenMetadata.ankyRevealed) revert AnkyAlreadyRevealed();
        
        tokenMetadata.imageURI = imageURI;
        tokenMetadata.ankyRevealed = true;
    }

    // Returns the token URI with metadata
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (id != 1 || !minted) revert InvalidTokenId();
        
        string memory image = tokenMetadata.ankyRevealed ? 
            string.concat('", "image": "', tokenMetadata.imageURI) :
            '", "image": "ipfs://QmS2vEhFTHRtRfCcghVwHEwjm2iE4pPyQHFpHe1p2yDtzx';
            
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name": "Anky Framesgiving #1",',
                        '"description": "A unique piece generated from an 8 minute writing session",',
                        '"writing_hash": "',
                        tokenMetadata.writingHash,
                        image,
                        '"}'
                    )
                )
            )
        );
    }

    // Returns collection-level metadata
    function contractURI() public pure returns (string memory) {
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name": "Anky Framesgiving", ',
                        '"description": "A unique piece generated from an 8 minute writing session"}'
                    )
                )
            )
        );
    }

    // Internal helper for token ownership checks
    function _ownerOf(uint256 id) internal view virtual override returns (address owner_) {
        if (id == 1 && minted) {
            return ownerOf(1);
        }
        return address(0);
    }
}
