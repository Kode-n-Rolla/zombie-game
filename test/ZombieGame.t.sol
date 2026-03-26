// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ZombieGame} from "../src/ZombieGame.sol";
import {ReentrantAttackReceiver} from "./ReentrantAttackReceiver.sol";

contract ZombieGameTest is Test {
    ZombieGame internal game;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        game = new ZombieGame();
    }

    // Happy path

    function test_claimStarterZombie_MintsStarterToCaller() public {
        vm.prank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        assertEq(zombieId, 1);
        assertEq(game.ownerOf(zombieId), alice);
        assertEq(game.balanceOf(alice), 1);
        assertTrue(game.hasClaimedStarter(alice));

        ZombieGame.Zombie memory zombie = game.getZombie(zombieId);
        assertEq(zombie.name, "Alice");
        assertEq(zombie.level, 1);
        assertEq(zombie.wins, 0);
        assertEq(zombie.losses, 0);
    }

    function test_claimStarterZombie_RevertsOnSecondClaim() public {
        vm.startPrank(alice);
        game.claimStarterZombie("Alice");

        vm.expectRevert(ZombieGame.AlreadyClaimedStarter.selector);
        game.claimStarterZombie("Alice II");
        vm.stopPrank();
    }

    function test_renameZombie_RevertsWhenCallerIsNotOwnerOrLevelTooLow() public {
        vm.prank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.NotZombieOwner.selector, zombieId, bob));
        game.renameZombie(zombieId, "Nope");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ZombieGame.RenameLevelTooLow.selector, zombieId, uint32(1), uint32(2))
        );
        game.renameZombie(zombieId, "Evolved");
    }

    function test_attack_UsesPreviewOutcomeAndTriggersCooldown() public {
        (uint256 attackerId, uint256 defenderId) = _claimDefaultZombies();

        vm.warp(block.timestamp + 1 days + 1);

        (uint256 attackerPowerBefore, uint256 defenderPowerBefore) = game.previewBattle(attackerId, defenderId);

        vm.prank(alice);
        (bool attackerWon, uint256 spawnedZombieId) = game.attack(attackerId, defenderId);

        ZombieGame.Zombie memory attacker = game.getZombie(attackerId);
        ZombieGame.Zombie memory defender = game.getZombie(defenderId);

        assertEq(attackerWon, attackerPowerBefore >= defenderPowerBefore);
        assertGt(attacker.readyTime, uint64(block.timestamp));

        if (attackerWon) {
            assertEq(attacker.level, 2);
            assertEq(attacker.wins, 1);
            assertEq(defender.losses, 1);
            assertEq(spawnedZombieId, 3);
            assertEq(game.ownerOf(spawnedZombieId), alice);
        } else {
            assertEq(attacker.level, 1);
            assertEq(attacker.losses, 1);
            assertEq(defender.wins, 1);
            assertEq(spawnedZombieId, 0);
        }

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotReady.selector, attackerId, attacker.readyTime));
        game.attack(attackerId, defenderId);
    }

    function test_transferFrom_MovesGameplayAuthority() public {
        vm.prank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        vm.prank(alice);
        game.transferFrom(alice, bob, zombieId);

        assertEq(game.ownerOf(zombieId), bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.NotZombieOwner.selector, zombieId, alice));
        game.renameZombie(zombieId, "Old Owner");
    }

    function _claimDefaultZombies() internal returns (uint256 attackerId, uint256 defenderId) {
        vm.prank(alice);
        attackerId = game.claimStarterZombie("Alice");

        vm.prank(bob);
        defenderId = game.claimStarterZombie("Bob");
    }

    // Authorization and revert paths

    function test_renameZombie_RevertsWhenNameIsEmpty() public {
        (address winner, uint256 winnerId) = _levelUpOneZombie();

        vm.prank(winner);
        vm.expectRevert(ZombieGame.EmptyName.selector);
        game.renameZombie(winnerId, "");
    }

    function test_renameZombie_RevertsWhenNameExceedsMaxLength() public {
        (address winner, uint256 winnerId) = _levelUpOneZombie();

        vm.prank(winner);
        vm.expectRevert(ZombieGame.NameTooLong.selector);
        game.renameZombie(winnerId, "Just Test the longer name for Alice`s zombie");
    }

    function test_getZombieAndIsReady_RevertForNonexistentTokenId() public {
        uint256 zombieId = 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotFound.selector, zombieId));
        game.getZombie(zombieId);

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotFound.selector, zombieId));
        game.isReady(zombieId);
    }

    function test_previewBattle_RevertsWhenDefenderDoesNotExist() public {
        uint256 anotherZombieId = 2;
        vm.startPrank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotFound.selector, anotherZombieId));
        game.previewBattle(zombieId, anotherZombieId);
    }

    function test_attack_RevertsWhenCallerIsNotAttackerOwner() public {
        vm.prank(alice);
        uint256 alicesZombie = game.claimStarterZombie("Alice");

        vm.startPrank(bob);
        uint256 bobsZombie = game.claimStarterZombie("Bob");
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.NotZombieOwner.selector, alicesZombie, bob));
        game.attack(alicesZombie, bobsZombie);
    }

    function test_attack_RevertsOnSelfAttack() public {
        vm.startPrank(alice);
        uint256 alicesZombie = game.claimStarterZombie("Alice");

        vm.expectRevert(abi.encodeWithSelector(ZombieGame.SelfAttack.selector));
        game.attack(alicesZombie, alicesZombie);
        vm.stopPrank();
    }

    function test_attack_RevertsWhenDefenderDoesNotExist() public {
        uint256 nonExistedZombieId = 2;
        vm.startPrank(alice);
        uint256 alicesZombie = game.claimStarterZombie("Alice");
        
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotFound.selector, nonExistedZombieId));
        game.attack(alicesZombie, nonExistedZombieId);
        vm.stopPrank();
    }

    function test_renameZombie_UpdatesNameAfterLevelRequirementMet() public {
        vm.prank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        vm.prank(bob);
        uint256 defenderId = game.claimStarterZombie("Bob");

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(alice);
        game.attack(zombieId, defenderId);


        vm.prank(alice);
        game.renameZombie(zombieId, "New_Alice");
        ZombieGame.Zombie memory zombie = game.getZombie(zombieId);

        assertEq("New_Alice", zombie.name);
    }

    function test_setBaseURI_RevertsWhenCallerIsNotOwner() public {
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, carol));
        game.setBaseURI("");
    }

    function test_tokenURI_UsesUpdatedBaseURI() public {
        vm.prank(alice);
        uint256 zombieId = game.claimStarterZombie("Alice");

        assertEq(game.tokenURI(zombieId), "");

        game.setBaseURI("https://api.zombie-game.xyz/metadata/");
        assertEq(game.tokenURI(zombieId), "https://api.zombie-game.xyz/metadata/1");
    }

    function test_attack_LossPathUpdatesStatsWithoutMint() public {
        (uint256 alicesZombie, uint256 bobsZombie) = _claimDefaultZombies();
        vm.warp(block.timestamp + 1 days + 1);

        (uint256 alicePower, uint256 bobPower) = game.previewBattle(alicesZombie, bobsZombie);

        address losingOwner;
        uint256 losingZombie;
        uint256 winningZombie;

        if (alicePower < bobPower) {
            losingOwner = alice;
            losingZombie = alicesZombie;
            winningZombie = bobsZombie;
        } else if (bobPower < alicePower) {
            losingOwner = bob;
            losingZombie = bobsZombie;
            winningZombie = alicesZombie;
        } else {
            losingOwner = bob;
            losingZombie = bobsZombie;
            winningZombie = alicesZombie;
        }

        ZombieGame.Zombie memory loserBefore = game.getZombie(losingZombie);
        ZombieGame.Zombie memory winnerBefore = game.getZombie(winningZombie);

        vm.prank(losingOwner);
        (bool attackerWon, uint256 spawnedZombieId) = game.attack(losingZombie, winningZombie);

        ZombieGame.Zombie memory loserAfter = game.getZombie(losingZombie);
        ZombieGame.Zombie memory winnerAfter = game.getZombie(winningZombie);

        assertFalse(attackerWon, "loss-path attacker should not win");
        assertEq(spawnedZombieId, 0, "loss path must not mint a reward zombie");
        assertEq(loserAfter.level, loserBefore.level, "loser level should not increase");
        assertEq(loserAfter.losses, loserBefore.losses + 1, "loser loss count should increment");
        assertEq(winnerAfter.wins, winnerBefore.wins + 1, "defender win count should increment");

        vm.expectRevert(abi.encodeWithSelector(ZombieGame.ZombieNotFound.selector, 3));
        game.getZombie(3);
    }

    function test_attack_AllowsTransferredZombieForNewOwnerOnly() public {
        vm.startPrank(alice);
        uint256 zombieId = game.claimStarterZombie("To_transfer");

        game.transferFrom(alice, carol, zombieId);

        vm.stopPrank();

        address ownerAfterTransfer = game.ownerOf(zombieId);

        assertEq(carol, ownerAfterTransfer);

        vm.prank(bob);
        uint256 bobsZombie = game.claimStarterZombie("Bob");

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(carol);
        game.attack(zombieId, bobsZombie);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZombieGame.NotZombieOwner.selector, zombieId, alice));
        game.attack(zombieId, bobsZombie);
    }

    function _levelUpOneZombie() internal returns (address winner, uint256 winnerId) {
        (uint256 alicesZombie, uint256 bobsZombie) = _claimDefaultZombies();
        vm.warp(block.timestamp + 1 days + 1);

        (uint256 alicePower, uint256 bobPower) = game.previewBattle(alicesZombie, bobsZombie);

        if (alicePower >= bobPower) {
            vm.prank(alice);
            game.attack(alicesZombie, bobsZombie);
            return (alice, alicesZombie);
        }

        vm.prank(bob);
        game.attack(bobsZombie, alicesZombie);
        return (bob, bobsZombie);
    }

    // Security properties

    function test_attack_AllowsDifferentZombiesOwnedBySamePlayer() public {
        vm.startPrank(alice);
        uint256 zombie1 = game.claimStarterZombie("Zombie_1");
        game.transferFrom(alice, carol, zombie1);

        vm.stopPrank();

        vm.startPrank(carol);
        uint256 zombie2 = game.claimStarterZombie("Zombie_2");

        vm.warp(block.timestamp + 1 days + 1);

        assertEq(game.ownerOf(zombie1), game.ownerOf(zombie2), "both zombies should belong to the same owner");
        game.attack(zombie1, zombie2);

        vm.stopPrank();
    }

    function test_previewBattle_MatchesAttackOutcome() public {
        (uint256 attackerId, uint256 defenderId) = _claimDefaultZombies();
        vm.warp(block.timestamp + 1 days + 1);

        (uint256 attackerPower, uint256 defenderPower) = game.previewBattle(attackerId, defenderId);

        vm.prank(alice);
        (bool attackerWon, ) = game.attack(attackerId, defenderId);

        assertEq(attackerWon, attackerPower >= defenderPower, "preview should match deterministic attack outcome");
    }

    function test_claimStarterZombie_SameAddressCanGrindStarterDnaWithDifferentNames() public view {
        string memory weakName = _findNameForScore(alice, 0, "weak-");
        string memory strongName = _findNameForScore(alice, 900, "strong-");

        uint64 weakDna = _starterDna(alice, weakName);
        uint64 strongDna = _starterDna(alice, strongName);

        uint256 powerA = _battlePower(weakDna, 1, 0);
        uint256 powerB = _battlePower(strongDna, 1, 0);

        assertNotEq(weakDna, strongDna, "different names should produce different starter DNA");
        assertNotEq(powerA, powerB, "different starter DNA should change initial battle power");
        assertEq(powerA, 3, "searched weak name should produce the minimum initial score");
        assertEq(powerB, 903, "searched strong name should produce a much stronger initial score");
    }

    function test_attack_ReentrancyDuringSafeMintBypassesCooldown() public {
        ReentrantAttackReceiver attacker = new ReentrantAttackReceiver(game);

        string memory attackerName = _findNameForScore(address(attacker), 900, "attacker-");
        string memory defenderName = _findNameForScore(bob, 0, "defender-");

        uint256 attackerId = attacker.claimStarterZombie(attackerName);

        vm.prank(bob);
        uint256 defenderId = game.claimStarterZombie(defenderName);

        (uint256 attackerPower, uint256 defenderPower) = game.previewBattle(attackerId, defenderId);
        assertGt(attackerPower, defenderPower, "attacker must win to trigger reward mint reentrancy");

        attacker.configureAttack(attackerId, defenderId, 1);

        vm.warp(block.timestamp + 1 days + 1);
        attacker.executeAttack();

        ZombieGame.Zombie memory attackerZombie = game.getZombie(attackerId);
        ZombieGame.Zombie memory defenderZombie = game.getZombie(defenderId);

        assertEq(attacker.reentryCount(), 1, "receiver hook should reenter exactly once");
        assertEq(game.balanceOf(address(attacker)), 3, "reentrancy should mint two extra zombies to the attacker");
        assertEq(attackerZombie.level, 3, "reentrant double win should raise attacker to level three");
        assertEq(attackerZombie.wins, 2, "reentrant callback should record two wins");
        assertEq(defenderZombie.losses, 2, "defender should record two losses from the chained attacks");
    }

    function _starterDna(address player, string memory name) internal view returns (uint64 dna) {
        dna = uint64(uint256(keccak256(abi.encodePacked(block.chainid, player, name))) % game.DNA_MODULUS());
        dna -= dna % 100;
    }

    function _battlePower(uint64 dna, uint32 level, uint16 wins) internal pure returns (uint256) {
        return uint256(level) * 3 + uint256(wins) * 2 + uint256(dna % 1000);
    }

    function _findNameForScore(address player, uint256 targetScore, string memory prefix) internal view returns (string memory) {
        for (uint256 i = 0; i < 10_000; i++) {
            string memory candidate = string.concat(prefix, vm.toString(i));
            if (_starterDna(player, candidate) % 1000 == targetScore) {
                return candidate;
            }
        }

        revert("name search failed");
    }

}
