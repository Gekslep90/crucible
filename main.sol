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
