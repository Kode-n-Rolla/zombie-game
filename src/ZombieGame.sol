// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

/// @title ZombieGame
/// @notice Compact zombie battler MVP with ERC721 ownership and deterministic combat.
/// @dev Combat is intentionally deterministic for testability. Secure randomness is postponed to a later version.
contract ZombieGame is ERC721, Ownable {
    uint256 public constant DNA_MODULUS = 10 ** 16;
    uint64 public constant COOLDOWN_TIME = 1 days;
    uint32 public constant STARTING_LEVEL = 1;
    uint32 public constant RENAME_LEVEL = 2;
    uint256 public constant MAX_NAME_LENGTH = 32;

    uint256 private _nextZombieId = 1;
    string private _baseTokenUri;

    mapping(uint256 zombieId => Zombie) private _zombies;
    mapping(address player => bool) public hasClaimedStarter;

    struct Zombie {
        string name;
        uint64 dna;
        uint32 level;
        uint64 readyTime;
        uint16 wins;
        uint16 losses;
    }

    event ZombieCreated(uint256 indexed zombieId, address indexed owner, string name, uint64 dna);
    event AttackResolved(
        uint256 indexed attackerId,
        uint256 indexed defenderId,
        bool attackerWon,
        uint256 attackerPower,
        uint256 defenderPower,
        uint256 spawnedZombieId
    );
    event NameChanged(uint256 indexed zombieId, string newName);
    event BaseURIUpdated(string newBaseURI);

    error AlreadyClaimedStarter();
    error EmptyName();
    error NameTooLong();
    error NotZombieOwner(uint256 zombieId, address caller);
    error ZombieNotFound(uint256 zombieId);
    error ZombieNotReady(uint256 zombieId, uint64 readyTime);
    error SelfAttack();
    error RenameLevelTooLow(uint256 zombieId, uint32 currentLevel, uint32 requiredLevel);

    constructor() ERC721("Zombie Game", "ZMB") Ownable(msg.sender) {}

    /// @notice Claims the caller's starter zombie. One per address.
    function claimStarterZombie(string calldata name) external returns (uint256 zombieId) {
        _validateName(name);

        if (hasClaimedStarter[msg.sender]) {
            revert AlreadyClaimedStarter();
        }

        hasClaimedStarter[msg.sender] = true;
        zombieId = _mintZombie(msg.sender, name, _starterDna(msg.sender, name));
    }

    /// @notice Resolves combat between two zombies and spawns a reward zombie on attacker victory.
    /// @return attackerWon Whether the attacker won the battle.
    /// @return spawnedZombieId The newly minted zombie id, or 0 if no zombie was spawned.
    function attack(
        uint256 attackerId,
        uint256 defenderId
    ) external returns (bool attackerWon, uint256 spawnedZombieId) {
        _requireZombieOwner(attackerId, msg.sender);
        _requireZombieExists(defenderId);

        if (attackerId == defenderId) {
            revert SelfAttack();
        }

        Zombie storage attacker = _zombies[attackerId];
        Zombie storage defender = _zombies[defenderId];

        if (!_isReady(attacker)) {
            revert ZombieNotReady(attackerId, attacker.readyTime);
        }

        (uint256 attackerPower, uint256 defenderPower) = previewBattle(attackerId, defenderId);
        attackerWon = attackerPower >= defenderPower;

        if (attackerWon) {
            unchecked {
                attacker.wins += 1;
                attacker.level += 1;
                defender.losses += 1;
            }

            spawnedZombieId = _mintZombie(msg.sender, "Spawnling", _combineDna(attacker.dna, defender.dna));
        } else {
            unchecked {
                attacker.losses += 1;
                defender.wins += 1;
            }
        }

        attacker.readyTime = uint64(block.timestamp + COOLDOWN_TIME);

        emit AttackResolved(
            attackerId,
            defenderId,
            attackerWon,
            attackerPower,
            defenderPower,
            spawnedZombieId
        );
    }

    /// @notice Renames a zombie once it has reached the required level.
    function renameZombie(uint256 zombieId, string calldata newName) external {
        _requireZombieOwner(zombieId, msg.sender);
        _validateName(newName);

        Zombie storage zombie = _zombies[zombieId];
        if (zombie.level < RENAME_LEVEL) {
            revert RenameLevelTooLow(zombieId, zombie.level, RENAME_LEVEL);
        }

        zombie.name = newName;
        emit NameChanged(zombieId, newName);
    }

    /// @notice Returns the current zombie data for a token.
    function getZombie(uint256 zombieId) external view returns (Zombie memory) {
        _requireZombieExists(zombieId);
        return _zombies[zombieId];
    }

    /// @notice Returns whether the zombie can attack right now.
    function isReady(uint256 zombieId) external view returns (bool) {
        _requireZombieExists(zombieId);
        return _isReady(_zombies[zombieId]);
    }

    /// @notice Returns the deterministic battle outcome and underlying power values.
    function previewBattle(
        uint256 attackerId,
        uint256 defenderId
    ) public view returns (uint256 attackerPower, uint256 defenderPower) {
        _requireZombieExists(attackerId);
        _requireZombieExists(defenderId);

        attackerPower = _battlePower(_zombies[attackerId]);
        defenderPower = _battlePower(_zombies[defenderId]);
    }

    /// @notice Owner-controlled base URI for optional metadata hosting.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenUri = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
    }

    function _mintZombie(address to, string memory name, uint64 dna) internal returns (uint256 zombieId) {
        zombieId = _nextZombieId;
        unchecked {
            _nextZombieId = zombieId + 1;
        }

        _zombies[zombieId] = Zombie({
            name: name,
            dna: dna,
            level: STARTING_LEVEL,
            readyTime: uint64(block.timestamp + COOLDOWN_TIME),
            wins: 0,
            losses: 0
        });

        _safeMint(to, zombieId);
        emit ZombieCreated(zombieId, to, name, dna);
    }

    function _starterDna(address player, string memory name) internal view returns (uint64 dna) {
        // forge-lint: disable-next-line(unsafe-typecast)
        dna = uint64(uint256(keccak256(abi.encodePacked(block.chainid, player, name))) % DNA_MODULUS);
        dna -= dna % 100;
    }

    function _combineDna(uint64 attackerDna, uint64 defenderDna) internal pure returns (uint64) {
        uint64 dna = uint64((uint256(attackerDna) + uint256(defenderDna)) / 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(dna % DNA_MODULUS);
    }

    function _battlePower(Zombie storage zombie) internal view returns (uint256) {
        return uint256(zombie.level) * 3 + uint256(zombie.wins) * 2 + uint256(zombie.dna % 1000);
    }

    function _isReady(Zombie storage zombie) internal view returns (bool) {
        return zombie.readyTime <= block.timestamp;
    }

    function _validateName(string memory name) internal pure {
        uint256 length = bytes(name).length;
        if (length == 0) {
            revert EmptyName();
        }
        if (length > MAX_NAME_LENGTH) {
            revert NameTooLong();
        }
    }

    function _requireZombieOwner(uint256 zombieId, address caller) internal view {
        address zombieOwner = _ownerOf(zombieId);
        if (zombieOwner == address(0)) {
            revert ZombieNotFound(zombieId);
        }
        if (zombieOwner != caller) {
            revert NotZombieOwner(zombieId, caller);
        }
    }

    function _requireZombieExists(uint256 zombieId) internal view {
        if (_ownerOf(zombieId) == address(0)) {
            revert ZombieNotFound(zombieId);
        }
    }
}
