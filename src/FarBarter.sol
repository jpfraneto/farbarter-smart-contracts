// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC1155 } from "solady/src/tokens/ERC1155.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { LibString } from "solady/src/utils/LibString.sol";

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
    PaymentPreference paymentPref;
  }

  struct UserProfile {
    uint256 reputation;
    uint256 totalSales;
    uint256 totalPurchases;
    bool isTrusted;
    uint256 lastActivityAt;
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
  }

  // State variables
  mapping(uint256 => Listing) public listings;
  mapping(uint256 => Listing[]) public listingsByFid;
  mapping(address => UserProfile) public userProfiles;
  mapping(uint256 => mapping(address => bool)) public hasPurchased;
  mapping(uint256 => Escrow) public escrows;

  uint256 public nextListingId;
  uint256 public nextEscrowId;
  uint256 public constant REPUTATION_THRESHOLD = 100;
  uint256 public constant DISPUTE_TIMELOCK = 7 days;

  // Events
  event ListingCreated(uint256 indexed listingId, address indexed seller, uint256 indexed fid, uint256 price, uint256 supply, string metadata, address preferredToken, uint256 preferredChain);

  event ListingPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity, uint256 escrowId);

  event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 amount);

  event EscrowConfirmed(uint256 indexed escrowId, address indexed confirmedBy, bool isBuyer);

  event EscrowCompleted(uint256 indexed escrowId, uint256 amount);

  event DisputeRaised(uint256 indexed escrowId, address indexed raisedBy);

  event DisputeResolved(uint256 indexed escrowId, address indexed winner, string resolution);

  event ReputationUpdated(address indexed user, uint256 newReputation, string reason);

  constructor() {
    _initializeOwner(msg.sender);
  }

  function createListing(uint256 fid, uint256 price, uint256 supply, string calldata metadata, address preferredToken, uint256 preferredChain) external returns (uint256) {
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
      paymentPref: paymentPref
    });

    listings[listingId] = listing;
    listingsByFid[fid].push(listing);

    emit ListingCreated(listingId, msg.sender, fid, price, supply, metadata, preferredToken, preferredChain);

    return listingId;
  }

  function purchase(uint256 listingId, uint256 quantity) external payable {
    Listing storage listing = listings[listingId];
    require(listing.isActive, "Listing not active");
    require(listing.remainingSupply >= quantity, "Insufficient supply");
    require(msg.value >= listing.price * quantity, "Insufficient payment");

    listing.remainingSupply -= quantity;
    listing.totalSales += quantity;

    uint256 escrowId = nextEscrowId++;
    escrows[escrowId] = Escrow({
      buyer: msg.sender,
      seller: listing.seller,
      amount: msg.value,
      buyerConfirmed: false,
      sellerConfirmed: false,
      isDisputed: false,
      createdAt: block.timestamp,
      completedAt: 0
    });

    _mint(msg.sender, listingId, quantity, "");

    _updateUserProfile(msg.sender, false, quantity);
    _updateUserProfile(listing.seller, true, quantity);

    hasPurchased[listingId][msg.sender] = true;

    emit ListingPurchased(listingId, msg.sender, quantity, escrowId);
    emit EscrowCreated(escrowId, msg.sender, listing.seller, msg.value);
  }

  function confirmEscrow(uint256 escrowId) external {
    Escrow storage escrow = escrows[escrowId];
    require(msg.sender == escrow.buyer || msg.sender == escrow.seller, "Not authorized");
    require(!escrow.isDisputed, "Escrow is disputed");

    if (msg.sender == escrow.buyer) {
      escrow.buyerConfirmed = true;
      emit EscrowConfirmed(escrowId, msg.sender, true);
    } else {
      escrow.sellerConfirmed = true;
      emit EscrowConfirmed(escrowId, msg.sender, false);
    }

    if (escrow.buyerConfirmed && escrow.sellerConfirmed) {
      _completeEscrow(escrowId);
    }
  }

  function raiseDispute(uint256 escrowId) external {
    Escrow storage escrow = escrows[escrowId];
    require(msg.sender == escrow.buyer || msg.sender == escrow.seller, "Not authorized");
    require(!escrow.isDisputed, "Already disputed");
    require(escrow.completedAt == 0, "Already completed");

    escrow.isDisputed = true;
    emit DisputeRaised(escrowId, msg.sender);
  }

  function resolveDispute(uint256 escrowId, address winner, string calldata resolution) external onlyOwner {
    Escrow storage escrow = escrows[escrowId];
    require(escrow.isDisputed, "Not disputed");
    require(winner == escrow.buyer || winner == escrow.seller, "Invalid winner");

    if (winner == escrow.seller) {
      SafeTransferLib.safeTransferETH(escrow.seller, escrow.amount);
    } else {
      SafeTransferLib.safeTransferETH(escrow.buyer, escrow.amount);
    }

    escrow.completedAt = block.timestamp;
    emit DisputeResolved(escrowId, winner, resolution);
  }

  function _completeEscrow(uint256 escrowId) internal {
    Escrow storage escrow = escrows[escrowId];
    require(!escrow.isDisputed, "Escrow is disputed");
    require(escrow.buyerConfirmed && escrow.sellerConfirmed, "Not confirmed");

    uint256 amount = escrow.amount;
    escrow.completedAt = block.timestamp;

    SafeTransferLib.safeTransferETH(escrow.seller, amount);

    emit EscrowCompleted(escrowId, amount);
  }

  function _updateUserProfile(address user, bool isSeller, uint256 quantity) internal {
    UserProfile storage profile = userProfiles[user];

    if (isSeller) {
      profile.totalSales += quantity;
      profile.reputation += quantity * 2;
    } else {
      profile.totalPurchases += quantity;
      profile.reputation += quantity;
    }

    profile.lastActivityAt = block.timestamp;
    profile.isTrusted = profile.reputation >= REPUTATION_THRESHOLD;

    emit ReputationUpdated(user, profile.reputation, isSeller ? "sale" : "purchase");
  }

  function getListingsByFid(uint256 fid) external view returns (Listing[] memory) {
    return listingsByFid[fid];
  }

  function isTrustedUser(address user) external view returns (bool) {
    return userProfiles[user].isTrusted;
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

  // Emergency escrow release after timelock
  function emergencyRelease(uint256 escrowId) external {
    Escrow storage escrow = escrows[escrowId];
    require(block.timestamp > escrow.createdAt + DISPUTE_TIMELOCK, "Timelock active");
    require(escrow.completedAt == 0, "Already completed");

    SafeTransferLib.safeTransferETH(escrow.buyer, escrow.amount);
    escrow.completedAt = block.timestamp;
  }
}
