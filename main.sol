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
