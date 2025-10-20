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

## Deployment

### DeployImplementations.s.sol

This script deploys and initializes all three upgradeable registries in one command:

- Deploys IdentityRegistryUpgradeable implementation
- Deploys ERC1967Proxy for IdentityRegistry with initialize()
- Deploys ReputationRegistryUpgradeable implementation
- Deploys ERC1967Proxy for ReputationRegistry with initialize(address identityProxy)
- Deploys ValidationRegistryUpgradeable implementation
- Deploys ERC1967Proxy for ValidationRegistry with initialize(address identityProxy)
- Logs all proxy and implementation addresses and verifies versions

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

Optionally export them for the verification step:

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

## Verifying Contracts (Hedera-friendly)

We recommend Sourcify for Hedera networks. Make sure your build settings (optimizer, via_ir) in `foundry.toml` match those used during deployment.

Chain IDs:

- Hedera Mainnet: 295
- Hedera Testnet: 296
- Hedera Previewnet: 297

### Verify Implementations (Sourcify)

```bash
# Identity implementation
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$ID_IMPL" \
  src/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable

# Reputation implementation
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$REP_IMPL" \
  src/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable

# Validation implementation
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$VAL_IMPL" \
  src/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable
```

### Prepare initializer calldata for proxies

- Identity initializer (no args): `initialize()`
- Reputation initializer (address): `initialize(address identityProxy)`
- Validation initializer (address): `initialize(address identityProxy)`

```bash
# Build init calldata including 4-byte selector
IDENTITY_INIT=$(cast calldata "initialize()")
REPUTATION_INIT=$(cast calldata "initialize(address)" "$ID_PROXY")
VALIDATION_INIT=$(cast calldata "initialize(address)" "$ID_PROXY")
```

### Verify Proxies (ERC1967Proxy via Sourcify)

Constructor signature: `(address implementation, bytes initCalldata)`

```bash
# Identity proxy
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$ID_PROXY" \
  src/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" "$ID_IMPL" "$IDENTITY_INIT")

# Reputation proxy
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$REP_PROXY" \
  src/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" "$REP_IMPL" "$REPUTATION_INIT")

# Validation proxy
forge verify-contract \
  --chain-id 296 \
  --verifier sourcify \
  --verifier-url "https://server-verify.hashscan.io/" \
  "$VAL_PROXY" \
  src/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" "$VAL_IMPL" "$VALIDATION_INIT")
```

## License

CC0 - Public Domain
