// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {ZombieGame} from "../src/ZombieGame.sol";

/// @notice Helper contract for testing win-path reentrancy through ERC721Receiver callbacks.
contract ReentrantAttackReceiver is IERC721Receiver {
    ZombieGame public immutable game;

    uint256 public attackerId;
    uint256 public defenderId;
    uint256 public reentryCount;
    uint256 public maxReentries;
    bool public attackConfigured;

    constructor(ZombieGame game_) {
        game = game_;
    }

    function claimStarterZombie(string calldata name) external returns (uint256 zombieId) {
        zombieId = game.claimStarterZombie(name);
        attackerId = zombieId;
    }

    function configureAttack(uint256 attackerId_, uint256 defenderId_, uint256 maxReentries_) external {
        attackerId = attackerId_;
        defenderId = defenderId_;
        maxReentries = maxReentries_;
        reentryCount = 0;
        attackConfigured = true;
    }

    function executeAttack() external returns (bool attackerWon, uint256 spawnedZombieId) {
        return game.attack(attackerId, defenderId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        if (attackConfigured && reentryCount < maxReentries) {
            reentryCount += 1;
            game.attack(attackerId, defenderId);
        }

        return IERC721Receiver.onERC721Received.selector;
    }
}
