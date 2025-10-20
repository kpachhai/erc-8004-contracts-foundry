# ERC-8004

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

## Foundry Quickstart

Prerequisites:

- Install Foundry:
  ```
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- Install dependencies:
  ```
  forge install foundry-rs/forge-std
  forge install OpenZeppelin/openzeppelin-contracts
  forge install OpenZeppelin/openzeppelin-contracts-upgradeable
  ```

Build:

```bash
forge build
```

Tip for complex code paths: enable via-IR and set a fixed solc in `foundry.toml` to avoid “stack too deep” and to help verification.

```
[profile.default]
optimizer = true
optimizer_runs = 200
via_ir = true
solc_version = "0.8.30"
```

## Deployment (single command)

### DeployImplementations.s.sol

This script deploys and initializes all three upgradeable registries in one command:

- Deploys IdentityRegistryUpgradeable implementation
- Deploys ERC1967Proxy for IdentityRegistry with initialize()
- Deploys ReputationRegistryUpgradeable implementation
- Deploys ERC1967Proxy for ReputationRegistry with initialize(address identityProxy)
- Deploys ValidationRegistryUpgradeable implementation
- Deploys ERC1967Proxy for ValidationRegistry with initialize(address identityProxy)
- Logs all proxy and implementation addresses and verifies versions

It leverages a small on-chain batch deployer contract (`scripts/ERC8004BatchDeployer.sol`) so everything happens within a single transaction on Hedera, avoiding relay receipt stalls.

Hedera Testnet (chainId 296) example:

```bash
forge script script/DeployImplementations.s.sol:DeployImplementations \
  --rpc-url "$HEDERA_RPC_URL" \
  --broadcast \
  --private-key "$HEDERA_PRIVATE_KEY" \
  --legacy \
  --gas-price 470000000000 \
  -vv
```

After a successful run, copy the printed addresses:

```text
IdentityRegistry Proxy:            0x...
ReputationRegistry Proxy:          0x...
ValidationRegistry Proxy:          0x...

IdentityRegistry Implementation:   0x...
ReputationRegistry Implementation: 0x...
ValidationRegistry Implementation: 0x...
```

Optionally export them for verification:

```bash
export ID_PROXY=0x...
export REP_PROXY=0x...
export VAL_PROXY=0x...

export ID_IMPL=0x...
export REP_IMPL=0x...
export VAL_IMPL=0x...
```

Notes for Hedera:

- Use `--legacy` transactions and a fixed gas price (e.g., 470 gwei = `470000000000` wei) for best reliability.
- If you change scripts/config, it’s safe to run `forge clean` before re-running.

## Verify (single command)

Run the helper script to verify all 3 implementations and 3 proxies on Hedera via Sourcify (HashScan’s verify server):

```bash
# Make sure the six env vars are set (see above)
./verify_all.sh
```

Defaults used by the script:

- CHAIN_ID=296 (override with `export CHAIN_ID=295|296|297`)
- VERIFIER_URL=https://server-verify.hashscan.io/
- SOURCE_DIR=src

### How verification works (under the hood)

The script performs the following actions:

1. Implementations (Sourcify)

```bash
forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$ID_IMPL"  $SOURCE_DIR/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable

forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$REP_IMPL" $SOURCE_DIR/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable

forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$VAL_IMPL" $SOURCE_DIR/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable
```

2. Proxies (constructor is `(address implementation, bytes initCalldata)`)

```bash
IDENTITY_INIT=$(cast calldata "initialize()")
REPUTATION_INIT=$(cast calldata "initialize(address)" "$ID_PROXY")
VALIDATION_INIT=$(cast calldata "initialize(address)" "$ID_PROXY")

forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$ID_PROXY"  $SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode 'constructor(address,bytes)' "$ID_IMPL"  "$IDENTITY_INIT")

forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$REP_PROXY" $SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode 'constructor(address,bytes)' "$REP_IMPL" "$REPUTATION_INIT")

forge verify-contract --chain-id $CHAIN_ID --verifier sourcify \
  --verifier-url "$VERIFIER_URL" \
  "$VAL_PROXY" $SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode 'constructor(address,bytes)' "$VAL_IMPL" "$VALIDATION_INIT")
```

## What is ERC8004BatchDeployer.sol?

`ERC8004BatchDeployer.sol` is a tiny contract used by `DeployImplementations.s.sol` to perform all six creations (3 implementations + 3 proxies) and initializations inside a single transaction. This is especially useful on Hedera where receipt polling can stall if many txs are in-flight(Note that this issue won't be there in the near future as a fix is in progress at the relay level). The batch deployer exposes the deployed addresses via public getters so the script can read and print them immediately after deployment.

## License

MIT
