// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibString } from "solady/utils/LibString.sol";

contract FarBarter is ERC1155, Ownable {
  using LibString for uint256;

  struct PaymentPreference {
    address token;
    uint256 chainId;
  }

  struct Listing {
    address seller;
    uint256 fid;
    uint256 price;
    uint256 supply;
    uint256 remainingSupply;
    string metadata;
    bool isActive;
    uint256 totalSales;
    uint256 createdAt;
    uint256 lastUpdatedAt;
    PaymentPreference paymentPref;
  }

  struct UserProfile {
    uint256 reputation;
    uint256 totalSales;
    uint256 totalPurchases;
    bool isTrusted;
    uint256 lastActivityAt;
    uint256 slashCount;
  }

  struct Escrow {
    address buyer;
    address seller;
    uint256 amount;
    bool buyerConfirmed;
    bool sellerConfirmed;
    bool isDisputed;
    uint256 createdAt;
    uint256 completedAt;
    uint256 listingId;
    uint256 buyerFid;
  }

  // State variables
  mapping(uint256 => Listing) public listings;
  mapping(uint256 => Listing[]) public listingsByFid;
  mapping(address => UserProfile) public userProfiles;
  mapping(uint256 => mapping(address => bool)) public hasPurchased;
  mapping(uint256 => Escrow) public escrows;
  mapping(address => mapping(uint256 => uint256)) public userPurchasesByBlock;
  mapping(uint256 => uint256) public listingPurchasesByBlock;

  uint256 public nextListingId;
  uint256 public nextEscrowId;
  uint256 public constant REPUTATION_THRESHOLD = 100;
  uint256 public constant DISPUTE_TIMELOCK = 7 days;
  uint256 public constant MAX_BLOCK_PURCHASES = 5;
  uint256 public constant MAX_PRICE = 0.1 ether;
  uint256 public constant MIN_PRICE = 0.0001 ether;
  uint256 public constant PROTOCOL_FEE_BPS = 250; // 2.5%
  uint256 public constant SLASH_THRESHOLD = 3;

  bool public paused;
  address public treasury;

  // Events
  event ListingCreated(uint256 indexed listingId, address indexed seller, uint256 indexed fid, uint256 price, uint256 supply, string metadata, address preferredToken, uint256 preferredChain);
  event ListingUpdated(uint256 indexed listingId, uint256 newPrice);
  event ListingCancelled(uint256 indexed listingId);
  event ListingPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity, uint256 escrowId);
  event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 amount);
  event EscrowConfirmed(uint256 indexed escrowId, address indexed confirmedBy, bool isBuyer);
  event EscrowCompleted(uint256 indexed escrowId, uint256 amount);
  event DisputeRaised(uint256 indexed escrowId, address indexed raisedBy);
  event DisputeResolved(uint256 indexed escrowId, address indexed winner, string resolution);
  event ReputationUpdated(address indexed user, uint256 newReputation, string reason);
  event UserSlashed(address indexed user, string reason);
  event EmergencyWithdraw(address indexed recipient, uint256 amount);
  event ProtocolFeeCollected(uint256 amount);

  // Custom errors
  error InvalidPrice();
  error InvalidQuantity();
  error InsufficientPayment();
  error ListingNotActive();
  error ContractPaused();
  error DisputeInProgress();
  error TimelockActive();
  error AlreadyConfirmed();
  error ExcessiveBlockPurchases();
  error SlashThresholdExceeded();
  error InvalidEscrow();

  // Modifiers
  modifier whenNotPaused() {
    if (paused) revert ContractPaused();
    _;
  }

  modifier validListing(uint256 listingId) {
    if (!listings[listingId].isActive) revert ListingNotActive();
    _;
  }

  modifier validEscrow(uint256 escrowId) {
    if (escrows[escrowId].buyer == address(0)) revert InvalidEscrow();
    _;
  }

  constructor() {
    _initializeOwner(msg.sender);
    treasury = 0xAdA8e0625D9c7EcCd1C5a9a7aC9fDD9756DBeC33;
  }

  function createListing(uint256 fid, uint256 price, uint256 supply, string calldata metadata, address preferredToken, uint256 preferredChain) external whenNotPaused returns (uint256) {
    if (preferredToken != address(0)) {
      // Minimal check that address contains code
      uint256 size;
      assembly {
        size := extcodesize(preferredToken)
      }
      require(size > 0, "Invalid token address");
    }
    if (price < MIN_PRICE || price > MAX_PRICE) revert InvalidPrice();
    if (supply == 0) revert InvalidQuantity();

    uint256 listingId = nextListingId++;

    PaymentPreference memory paymentPref = PaymentPreference({ token: preferredToken, chainId: preferredChain });

    Listing memory listing = Listing({
      seller: msg.sender,
      fid: fid,
      price: price,
      supply: supply,
      remainingSupply: supply,
      metadata: metadata,
      isActive: true,
      totalSales: 0,
      createdAt: block.timestamp,
      lastUpdatedAt: block.timestamp,
      paymentPref: paymentPref
    });

    listings[listingId] = listing;
    listingsByFid[fid].push(listing);

    emit ListingCreated(listingId, msg.sender, fid, price, supply, metadata, preferredToken, preferredChain);

    return listingId;
  }

  function updateListingPrice(uint256 listingId, uint256 newPrice) external validListing(listingId) whenNotPaused {
    Listing storage listing = listings[listingId];
    if (msg.sender != listing.seller) revert Unauthorized();
    if (newPrice < MIN_PRICE || newPrice > MAX_PRICE) revert InvalidPrice();

    listing.price = newPrice;
    listing.lastUpdatedAt = block.timestamp;

    emit ListingUpdated(listingId, newPrice);
  }

  function cancelListing(uint256 listingId) external validListing(listingId) whenNotPaused {
    Listing storage listing = listings[listingId];
    if (msg.sender != listing.seller) revert Unauthorized();

    listing.isActive = false;
    listing.lastUpdatedAt = block.timestamp;

    emit ListingCancelled(listingId);
  }

  function purchase(uint256 listingId, uint256 quantity, address buyerAddress, uint256 buyerFid) external payable whenNotPaused validListing(listingId) {
    // Validate FID ownership

    // Load state
    Listing storage listing = listings[listingId];
    uint256 totalPrice = listing.price * quantity;
    uint256 protocolFee = (totalPrice * PROTOCOL_FEE_BPS) / 10000;

    // Validations
    if (listing.remainingSupply < quantity) revert InvalidQuantity();
    if (msg.value < totalPrice + protocolFee) revert InsufficientPayment();
    if (userPurchasesByBlock[buyerAddress][block.number] + quantity > MAX_BLOCK_PURCHASES) revert ExcessiveBlockPurchases();
    if (listingPurchasesByBlock[listingId] + quantity > MAX_BLOCK_PURCHASES) revert ExcessiveBlockPurchases();

    // Update state
    listing.remainingSupply -= quantity;
    listing.totalSales += quantity;
    listing.lastUpdatedAt = block.timestamp;

    userPurchasesByBlock[buyerAddress][block.number] += quantity;
    listingPurchasesByBlock[listingId] += quantity;

    // Create escrow
    uint256 escrowId = nextEscrowId++;
    escrows[escrowId] = Escrow({
      buyer: buyerAddress,
      seller: listing.seller,
      amount: totalPrice,
      buyerConfirmed: false,
      sellerConfirmed: false,
      isDisputed: false,
      createdAt: block.timestamp,
      completedAt: 0,
      listingId: listingId,
      buyerFid: buyerFid
    });

    // Mint tokens and update profiles
    _mint(buyerAddress, listingId, quantity, "");
    _updateUserProfile(buyerAddress, false, quantity);
    _updateUserProfile(listing.seller, true, quantity);

    hasPurchased[listingId][buyerAddress] = true;

    // Transfer protocol fee
    SafeTransferLib.safeTransferETH(treasury, protocolFee);

    emit ListingPurchased(listingId, buyerAddress, quantity, escrowId);
    emit EscrowCreated(escrowId, buyerAddress, listing.seller, totalPrice);
    emit ProtocolFeeCollected(protocolFee);

    if (msg.value > totalPrice + protocolFee) {
      SafeTransferLib.safeTransferETH(msg.sender, msg.value - (totalPrice + protocolFee));
    }
  }

  function confirmEscrow(uint256 escrowId) external whenNotPaused validEscrow(escrowId) {
    Escrow storage escrow = escrows[escrowId];
    if (msg.sender != escrow.buyer && msg.sender != escrow.seller) revert Unauthorized();
    if (escrow.isDisputed) revert DisputeInProgress();

    if (msg.sender == escrow.buyer) {
      if (escrow.buyerConfirmed) revert AlreadyConfirmed();
      escrow.buyerConfirmed = true;
      emit EscrowConfirmed(escrowId, msg.sender, true);
    } else {
      if (escrow.sellerConfirmed) revert AlreadyConfirmed();
      escrow.sellerConfirmed = true;
      emit EscrowConfirmed(escrowId, msg.sender, false);
    }

    if (escrow.buyerConfirmed && escrow.sellerConfirmed) {
      _completeEscrow(escrowId);
    }
  }

  function raiseDispute(uint256 escrowId) external whenNotPaused validEscrow(escrowId) {
    Escrow storage escrow = escrows[escrowId];
    if (msg.sender != escrow.buyer && msg.sender != escrow.seller) revert Unauthorized();
    if (escrow.isDisputed) revert DisputeInProgress();
    if (escrow.completedAt != 0) revert("Already completed");

    escrow.isDisputed = true;
    emit DisputeRaised(escrowId, msg.sender);
  }

  function resolveDispute(uint256 escrowId, address winner, string calldata resolution) external onlyOwner whenNotPaused validEscrow(escrowId) {
    Escrow storage escrow = escrows[escrowId];
    if (!escrow.isDisputed) revert("Not disputed");
    if (winner != escrow.buyer && winner != escrow.seller) revert Unauthorized();

    address loser = winner == escrow.buyer ? escrow.seller : escrow.buyer;
    _slashUser(loser, "Lost dispute");

    if (winner == escrow.seller) {
      SafeTransferLib.safeTransferETH(escrow.seller, escrow.amount);
    } else {
      SafeTransferLib.safeTransferETH(escrow.buyer, escrow.amount);
    }

    escrow.completedAt = block.timestamp;
    emit DisputeResolved(escrowId, winner, resolution);
  }

  function emergencyRelease(uint256 escrowId) external whenNotPaused validEscrow(escrowId) {
    Escrow storage escrow = escrows[escrowId];
    if (block.timestamp <= escrow.createdAt + DISPUTE_TIMELOCK) revert TimelockActive();
    if (escrow.completedAt != 0) revert("Already completed");
    if (msg.sender != escrow.buyer && msg.sender != escrow.seller) revert Unauthorized();

    SafeTransferLib.safeTransferETH(escrow.buyer, escrow.amount);
    escrow.completedAt = block.timestamp;

    _slashUser(escrow.seller, "Failed to complete transaction");
  }

  function _completeEscrow(uint256 escrowId) internal {
    Escrow storage escrow = escrows[escrowId];
    if (escrow.isDisputed) revert DisputeInProgress();
    if (!escrow.buyerConfirmed || !escrow.sellerConfirmed) revert("Not confirmed");

    uint256 amount = escrow.amount;
    escrow.completedAt = block.timestamp;

    SafeTransferLib.safeTransferETH(escrow.seller, amount);

    emit EscrowCompleted(escrowId, amount);
  }

  function _slashUser(address user, string memory reason) internal {
    UserProfile storage profile = userProfiles[user];
    profile.slashCount++;
    profile.reputation = profile.reputation > 10 ? profile.reputation - 10 : 0;

    if (profile.slashCount >= SLASH_THRESHOLD) {
      profile.isTrusted = false;
    }

    emit UserSlashed(user, reason);
    emit ReputationUpdated(user, profile.reputation, "slashed");
  }

  function _updateUserProfile(address user, bool isSeller, uint256 quantity) internal {
    UserProfile storage profile = userProfiles[user];

    if (profile.slashCount >= SLASH_THRESHOLD) revert SlashThresholdExceeded();

    if (isSeller) {
      profile.totalSales += quantity;
      profile.reputation += quantity * 2;
    } else {
      profile.totalPurchases += quantity;
      profile.reputation += quantity;
    }

    profile.lastActivityAt = block.timestamp;
    profile.isTrusted = profile.reputation >= REPUTATION_THRESHOLD;

    emit ReputationUpdated(user, profile.reputation, isSeller ? "sale completed" : "purchase completed");
  }

  // View functions
  function getListingsByFid(uint256 fid) external view returns (Listing[] memory) {
    return listingsByFid[fid];
  }

  function isTrustedUser(address user) external view returns (bool) {
    return userProfiles[user].isTrusted && userProfiles[user].slashCount < SLASH_THRESHOLD;
  }

  function getListingDetails(
    uint256 listingId
  )
    external
    view
    returns (address seller, uint256 fid, uint256 price, uint256 remainingSupply, string memory metadata, bool isActive, uint256 totalSales, address preferredToken, uint256 preferredChain)
  {
    Listing storage listing = listings[listingId];
    return (listing.seller, listing.fid, listing.price, listing.remainingSupply, listing.metadata, listing.isActive, listing.totalSales, listing.paymentPref.token, listing.paymentPref.chainId);
  }

  function uri(uint256 id) public view virtual override returns (string memory) {
    return listings[id].metadata;
  }

  // Admin functions
  function setTreasury(address newTreasury) external onlyOwner {
    require(newTreasury != address(0), "Invalid treasury");
    treasury = newTreasury;
  }

  function setPaused(bool _paused) external onlyOwner {
    paused = _paused;
  }

  // Emergency functions
  function emergencyWithdraw() external onlyOwner {
    uint256 balance = address(this).balance;
    SafeTransferLib.safeTransferETH(treasury, balance);
    emit EmergencyWithdraw(treasury, balance);
  }

  // Function to support upgradeability
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165
      interfaceId == 0xd9b67a26 || // ERC1155
      interfaceId == 0x0e89341c; // ERC1155MetadataURI
  }

  // Function to transfer accidentally sent ERC20 tokens
  function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
    SafeTransferLib.safeTransfer(token, to, amount);
  }

  // Constants getter functions
  function getConstants()
    external
    pure
    returns (uint256 repThreshold, uint256 disputeLock, uint256 maxBlockPurchases, uint256 maxPrice, uint256 minPrice, uint256 protocolFeeBps, uint256 slashThreshold)
  {
    return (REPUTATION_THRESHOLD, DISPUTE_TIMELOCK, MAX_BLOCK_PURCHASES, MAX_PRICE, MIN_PRICE, PROTOCOL_FEE_BPS, SLASH_THRESHOLD);
  }

  // Recovery function for non-escrow ETH
  function recoverEth() external onlyOwner {
    uint256 balance = address(this).balance;
    require(balance > 0, "No ETH to recover");
    SafeTransferLib.safeTransferETH(treasury, balance);
  }

  // Receive function to accept ETH payments
  receive() external payable {}

  // Fallback function
  fallback() external payable {}
}
