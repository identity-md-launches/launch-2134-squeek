# Squeek (SQK)

Squeek is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 SQK with 18 decimals** once, entirely to the account creating it.

| Deployment property | Value |
| --- | --- |
| Contract / artifact | `src/Squeek.sol:Squeek` / `out/Squeek.sol/Squeek.json` |
| Solidity identifier | `Squeek` |
| Name / symbol | `Squeek` / `SQK` |
| Decimals | `18` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment transaction value | `0` |
| Initial recipient | Immediate creating account, `msg.sender` |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |
| Intended launch chain | Ethereum, chain ID 1 |

## Design and assumptions

`Squeek` inherits the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation. The only added behavior is the constructor mint, using the named constant `INITIAL_SUPPLY`. The constructor has no external calls or external contract dependencies. The compiled creation code needs no linked libraries.

The brief specifies no special transfer rules, so transfers use ordinary ERC-20 accounting: the sender loses exactly the amount the recipient receives, with no tax, fee, reflection, rebase, or automatic allocation. Zero-value transfers between valid addresses succeed and emit `Transfer`; self-transfers preserve the balance. Transfers to the zero address revert.

`approve` sets or replaces the caller's allowance and emits `Approval`. `transferFrom` requires the caller's allowance, including when the caller is also the source account. Finite allowances decrease by the amount spent; `type(uint256).max` remains unchanged. In this OpenZeppelin version, spending an allowance does not emit a new `Approval` event; integrations should query `allowance`. Invalid operations revert with ERC-6093 custom errors and leave balances and allowances unchanged.

There is no owner, mint entry point, burn entry point, pause, blacklist, seizure, upgrade, initialization, or rescue function. Total supply remains constant for the life of the deployed contract. Possessing the initial supply gives the deployer no authority over other holders. Approvals are the only way another account can spend a holder's tokens.

## Build and check

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xa27819f9a983464ec272f3036fe164ef9b1875d9825641edc4da90c3ceaa965d forge test
forge fmt --check
```

All Solidity dependencies are ordinary files under `lib/`; no package installation, network access, RPC endpoint, environment configuration, FFI, or filesystem cheatcode permissions are needed for the build or tests. The fuzz seed above is the assignment's reproducibility seed, not a dependency on an environment value read by a test. `foundry.toml` configures 1,024 cases per fuzz test and 128 invariant runs of depth 64.

`test/Squeek.t.sol` covers metadata, exact supply and mint event, direct deployment, CREATE2 factory deployment, distribution and claims, transfers, approvals, finite and infinite allowances, rejected operations and rollback, forbidden administrative entry points, runtime size/opcodes, and fuzzed amount boundaries. `test/Squeek.invariant.t.sol` compares balances and allowances with an independent model over sequences of transfers, approvals, delegated transfers, and failed overdrafts across five holders.

The factory harness and actors are local test fixtures, not deployment configuration. The distribution test checks token accounting in both directions; it does not implement a Uniswap pool or prove swap pricing. The supplied protected checks depend on the network's separate launch harness and manifest inputs and are not part of the standalone local suite.

## Deployment and operations

Deploy the artifact directly with no constructor arguments and no ETH. If an EOA creates it, that EOA receives the supply. If the launch factory creates it using CREATE or CREATE2, **the factory receives the entire supply**, not the transaction origin, requester, or a separately selected owner. A wrapper script or helper contract that creates Squeek would likewise receive all tokens; any such wrapper must be able to distribute them. The local CREATE2 test verifies this behavior.

For the specified IMD launch, the factory handles the 10% swarm allocation, 80% pool allocation, and 10% remainder outside the token constructor. This project does not allocate balances ahead of those factory transfers. The launch service supplies the manifest, deployment transaction, external pool configuration, and recipient details in its separate launch step; this repository contains no `launch.json` or broadcast script.

After creation, the deployer should verify `name`, `symbol`, `decimals`, `totalSupply`, the initial holder's balance, and the mint `Transfer` event against the values above, then perform the authorized distribution. The launch operator is responsible for source verification and the separate independent review before release. Local tests and source review are not a security audit. Slither and Mythril were not run for this deliverable.

### After launch

There are no owner settings, initialization calls, maintenance jobs, external services, or administrative keys. Holders are responsible for custody and approvals. Prefer bounded approvals; when changing an existing nonzero allowance, revoke it first, confirm that transaction, then grant the new amount to reduce the standard ERC-20 allowance replacement risk. Any approved spender can use its current allowance before revocation is confirmed.

Ordinary ETH transfers to the token revert. Tokens transferred to the token's own address, and any forcibly sent ETH, cannot be recovered through this contract. Integrators should validate recipients and amounts before sending. The token has no recipient callback, oracle, signature validation, or arbitrary external-call mechanism.

## Dependency provenance

- OpenZeppelin Contracts [v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2), commit `dbb6104ce834628e473d2173bbc9d47f81a9eec3`: only the ERC-20 import closure and MIT license are vendored.
- Forge Standard Library [v1.9.6](https://github.com/foundry-rs/forge-std/tree/v1.9.6), commit `3b20d60d14b343ee4f908cb8079495c07f5e8981`: Solidity test utilities and MIT/Apache licenses are vendored.

`dependencies.lock.json` records the upstream commits and SHA-256 hashes of every vendored file. Dependencies are unmodified. ERC-20 behavior follows [EIP-20](https://eips.ethereum.org/EIPS/eip-20) and the pinned implementation; no dependency fetch runs during verification.
