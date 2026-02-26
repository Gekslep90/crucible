// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Alchemist
 * @notice Transmutation lab: deposit reagents (wei), register recipes, keeper resolves transmutations; yield goes to crucible, fees to treasury. Chain-derived recipe nonce for uniqueness.
 * @dev Crucible, treasury, and keeper are set at deploy and are immutable. ReentrancyGuard and pause for mainnet safety.
 */

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/Pausable.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/access/Ownable.sol";

contract Alchemist is ReentrancyGuard, Pausable, Ownable {

    event RecipeInscribed(uint256 indexed recipeId, bytes32 formulaHash, uint256 minReagentWei, uint256 yieldBps, uint256 atBlock);
    event RecipeToggled(uint256 indexed recipeId, bool active, uint256 atBlock);
    event ReagentDeposited(address indexed depositor, bytes32 indexed vesselId, uint256 amountWei, uint256 atBlock);
    event TransmutationResolved(
        bytes32 indexed transmuteId,
        address indexed beneficiary,
        uint256 indexed recipeId,
        uint256 reagentWei,
        uint256 yieldWei,
        uint256 feeWei,
        uint256 atBlock
    );
    event CrucibleWithdrawn(address indexed to, uint256 amountWei, uint256 atBlock);
    event LabPauseToggled(bool paused);
    event FeeBpsUpdated(uint256 previousBps, uint256 newBps, uint256 atBlock);
    event VesselLabelUpdated(bytes32 indexed vesselId, bytes32 previousLabel, bytes32 newLabel, uint256 atBlock);
    event BatchRecipesInscribed(uint256[] recipeIds, uint256 atBlock);

    error ALCH_ZeroAddress();
    error ALCH_ZeroAmount();
    error ALCH_LabPaused();
    error ALCH_RecipeNotFound();
    error ALCH_RecipeInactive();
    error ALCH_InvalidFeeBps();
    error ALCH_TransferFailed();
    error ALCH_Reentrancy();
    error ALCH_NotKeeper();
    error ALCH_MaxRecipesReached();
    error ALCH_RecipeAlreadyExists();
    error ALCH_InsufficientReagent();
    error ALCH_ArrayLengthMismatch();
    error ALCH_BatchTooLarge();
    error ALCH_ZeroRecipes();
    error ALCH_VesselNotFound();
    error ALCH_InvalidYieldBps();
    error ALCH_InvalidFormula();

    uint256 public constant ALCH_BPS_BASE = 10000;
    uint256 public constant ALCH_MAX_FEE_BPS = 250;
    uint256 public constant ALCH_MAX_RECIPES = 72;
    uint256 public constant ALCH_RECIPE_SALT = 0x5C9f2E8a4D1b7F0e3A6c9B2d5E8f1A4c7D0e3B6;
    uint256 public constant ALCH_MAX_BATCH_INSCRIBE = 12;
    uint256 public constant ALCH_MIN_YIELD_BPS = 5000;
    uint256 public constant ALCH_MAX_YIELD_BPS = 10000;

    address public immutable crucible;
    address public immutable treasury;
    address public immutable labKeeper;
    uint256 public immutable deployedBlock;
    bytes32 public immutable labDomain;

    uint256 public recipeCounter;
    uint256 public feeBps;
    uint256 public transmuteSequence;
    bool public labPaused;

    struct RecipeRecord {
        bytes32 formulaHash;
        uint256 minReagentWei;
        uint256 yieldBps;
        uint256 inscribedAtBlock;
        bool active;
    }

    struct TransmuteSnapshot {
        bytes32 transmuteId;
        address beneficiary;
        uint256 recipeId;
        uint256 reagentWei;
        uint256 yieldWei;
        uint256 feeWei;
        uint256 atBlock;
    }

    mapping(uint256 => RecipeRecord) public recipes;
    mapping(bytes32 => TransmuteSnapshot) public transmuteSnapshots;
    mapping(uint256 => uint256) public recipeTransmuteCount;
    mapping(uint256 => uint256) public recipeVolumeWei;
    mapping(bytes32 => uint256) public vesselBalanceWei;
    mapping(bytes32 => bytes32) public vesselLabel;
    mapping(bytes32 => uint256) public vesselCreatedAtBlock;
    bytes32[] private _vesselIds;
    uint256[] private _recipeIds;

    modifier whenNotPaused() {
        if (labPaused) revert ALCH_LabPaused();
        _;
    }

    constructor() {
        crucible = address(0xE8f2A4C6b1D9e3F7a0B5c8E2d4F6A9b1C3e5D7);
        treasury = address(0x9C1e5F3a7B0d2E6f8A4c1B7e9D3F5a0C2E6b8);
        labKeeper = address(0x4F7b2D9e1A6c0E3f8B5d2A9c7E1F4b0D6e3A8);
        deployedBlock = block.number;
        labDomain = keccak256(abi.encodePacked("Alchemist_", block.chainid, block.prevrandao, ALCH_RECIPE_SALT));
        feeBps = 8;
    }

    function setLabPaused(bool paused) external onlyOwner {
        labPaused = paused;
        emit LabPauseToggled(paused);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > ALCH_MAX_FEE_BPS) revert ALCH_InvalidFeeBps();
        uint256 prev = feeBps;
        feeBps = newFeeBps;
        emit FeeBpsUpdated(prev, newFeeBps, block.number);
    }

    function inscribeRecipe(bytes32 formulaHash, uint256 minReagentWei, uint256 yieldBps) external onlyOwner returns (uint256 recipeId) {
        if (formulaHash == bytes32(0)) revert ALCH_InvalidFormula();
        if (yieldBps < ALCH_MIN_YIELD_BPS || yieldBps > ALCH_MAX_YIELD_BPS) revert ALCH_InvalidYieldBps();
        if (recipeCounter >= ALCH_MAX_RECIPES) revert ALCH_MaxRecipesReached();
        recipeId = ++recipeCounter;
        recipes[recipeId] = RecipeRecord({
            formulaHash: formulaHash,
            minReagentWei: minReagentWei,
            yieldBps: yieldBps,
            inscribedAtBlock: block.number,
