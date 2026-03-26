# Zombie Game

This repository is a compact Solidity/Foundry rebuild of the original CryptoZombies learning idea.

It is not a tutorial port.

The goal is to take a tutorial-era game concept and rebuild it as a small modern Solidity project with clearer architecture, better testability, and a more security-minded development process.

## Why This Project Exists

I use this project as a portfolio-oriented case study for three related skills:

- modernizing legacy/tutorial Solidity into a cleaner MVP
- designing contracts with testing and review in mind
- thinking about security as part of implementation, not only after the code is finished

The repo is intentionally small so the tradeoffs stay visible.

## What Was Modernized

Compared with the original tutorial-style architecture, this rebuild makes a few deliberate changes:

- upgraded to Solidity `0.8.24`
- replaced the inheritance ladder with one compact main contract
- replaced custom ownership and NFT logic with OpenZeppelin `ERC721` and `Ownable`
- removed tutorial-era abstractions that added complexity without helping the MVP
- kept the core game identity while making state transitions easier to test
- postponed unnecessary integrations and speculative V2 mechanics

## Design Philosophy

This project follows a few simple rules:

- readable over clever
- compact over over-engineered
- testable over feature-rich
- one clear contract over unnecessary modular theater
- explicit tradeoffs over fake production assumptions

For that reason, combat in the current MVP is deterministic.

That is intentional.

Using insecure block-derived pseudo-randomness would make the project look more game-like, but less honest from a security perspective. Deterministic logic is easier to reason about, easier to test, and makes design limitations obvious instead of hiding them behind weak entropy.

## Current Architecture

The MVP is centered around one main contract:

- `src/ZombieGame.sol`
  - OpenZeppelin-based ERC721 ownership
  - one starter zombie per address
  - zombie stats and progression
  - cooldown-gated attacks
  - deterministic battle resolution
  - rename gated by level

Supporting test files:

- `test/ZombieGame.t.sol`
  - functional tests
  - authorization and revert-path tests
  - security-oriented property tests
- `test/ReentrantAttackReceiver.sol`
  - helper contract for reentrancy testing

## Testing Philosophy

One of the main purposes of this repository is to show that happy-path coverage alone is not enough.

A contract can have strong-looking coverage for its intended flows and still miss important adversarial behavior. In practice, impactful bugs often appear in edge cases, cross-state transitions, callback surfaces, and assumptions that are true only during normal use.

This is why the test suite is split conceptually into:

- functional behavior tests
- authorization and revert-path tests
- security-oriented tests

An important lesson from this project is that adding security-focused tests may only move the coverage percentage a little, while increasing the actual review value much more.

If you want to include your `forge coverage` screenshots, this is the right place to compare:

- coverage with classic functional tests only
- coverage after adding security-oriented tests

The numerical delta may be small.

The assurance value is not.

## Security Notes

This repository is security-oriented, but it is still an MVP and not presented as production-ready game infrastructure.

Current important observations:

- combat is deterministic and fully previewable
- starter DNA can be optimized offchain by grinding names
- the reward mint path uses `_safeMint`, which creates a reentrancy surface during callback-based mint flows

These points are important for two reasons:

- they show where simple game logic can still create meaningful attack surface
- they demonstrate why security testing should not be treated as optional polish after functional tests pass

Some tests in this repository intentionally demonstrate weaknesses rather than proving the system is already safe.

That is deliberate.

## Known Limitations

This repository keeps the MVP small on purpose.

Not included in the current version:

- secure randomness design such as VRF or commit-reveal
- external DNA integrations
- production game economy mechanics
- upgradeability
- advanced metadata/gameplay modules

These are postponed because they would add complexity faster than they would improve the quality of the core MVP.

## Commands

```sh
forge build
forge test
forge coverage
forge fmt
```

If cloning with dependencies as submodules:

```sh
git submodule update --init --recursive
```

## Future Work

The most natural next steps are:

- fix the demonstrated reentrancy issue in the reward mint path
- redesign combat outcome generation if fair randomness becomes a goal
- add fuzzing and invariants for more adversarial test coverage
- expand gameplay only if it improves the architecture instead of bloating it
