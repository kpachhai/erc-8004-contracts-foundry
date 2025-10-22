#!/usr/bin/env bash
set -euo pipefail

# Defaults (override by exporting variables before running)
: "${CHAIN_ID:=296}"                         # 295 mainnet, 296 testnet, 297 previewnet
: "${VERIFIER_URL:=https://server-verify.hashscan.io/}"
: "${SOURCE_DIR:=src}"                       # set to 'contracts' if your sources live there
: "${SHOW_ERRORS:=1}"                        # 1 = show forge errors if verification fails

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need forge
need cast
need mktemp

# Required addresses from the deployment output
vars=(ID_IMPL REP_IMPL VAL_IMPL ID_PROXY REP_PROXY VAL_PROXY)
for v in "${vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Env var $v is required. Export all of: ${vars[*]}" >&2
    exit 1
  fi
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ok()    { printf "${GREEN}✔ %s${NC}\n" "$*"; }
info()  { printf "${YELLOW}ℹ %s${NC}\n" "$*"; }
fail()  { printf "${RED}✘ %s${NC}\n" "$*"; }

echo "== Verifying on chain $CHAIN_ID (Sourcify: $VERIFIER_URL)"
echo "Sources:  $SOURCE_DIR"
echo ""

echo "Addresses:"
printf "  ID_IMPL=%s\n  REP_IMPL=%s\n  VAL_IMPL=%s\n" "$ID_IMPL" "$REP_IMPL" "$VAL_IMPL"
printf "  ID_PROXY=%s\n  REP_PROXY=%s\n  VAL_PROXY=%s\n" "$ID_PROXY" "$REP_PROXY" "$VAL_PROXY"
echo ""

section() {
  local title="$1"
  printf "\n==================== %s ====================\n" "$title"
}

run_verify() {
  local label="$1" addr="$2" fqcn="$3"
  shift 3

  section "Verify: $label @ $addr"

  # Build and display the EXACT command that will be executed
  local cmd_str
  cmd_str="forge verify-contract --chain-id \"$CHAIN_ID\" --verifier sourcify --verifier-url \"$VERIFIER_URL\" \"$addr\" \"$fqcn\""
  for arg in "$@"; do
    cmd_str+=" \"$arg\""
  done
  echo "> $cmd_str"

  local tmp code
  tmp="$(mktemp)"

  # Execute (show full output), capture exit code and output for post-processing
  set +e
  forge verify-contract \
    --chain-id "$CHAIN_ID" \
    --verifier sourcify \
    --verifier-url "$VERIFIER_URL" \
    "$addr" "$fqcn" "$@" | tee "$tmp"
  code=${PIPESTATUS[0]}
  set -e

  if grep -qi "already verified" "$tmp"; then
    ok "Already verified: $label @ $addr"
  elif [[ $code -eq 0 ]]; then
    # Surface match quality if present
    if grep -qi "perfect match" "$tmp"; then
      ok "Verified (perfect match): $label @ $addr"
    elif grep -qi "partial match" "$tmp"; then
      ok "Verified (partial match): $label @ $addr"
    else
      ok "Verified: $label @ $addr"
    fi
  else
    fail "Failed: $label @ $addr"
    if [[ "$SHOW_ERRORS" -eq 1 ]]; then
      echo "---- forge output ----"
      # Optionally filter some standard noise lines if desired:
      sed '/Attempting to verify on Sourcify/d' "$tmp" | sed '/Pass the --etherscan-api-key/d'
      echo "----------------------"
    fi
    rm -f "$tmp"
    return 1
  fi

  rm -f "$tmp"
}

echo "== Building initializer calldata"
IDENTITY_INIT="$(cast calldata 'initialize()')"
REPUTATION_INIT="$(cast calldata 'initialize(address)' "$ID_PROXY")"
VALIDATION_INIT="$(cast calldata 'initialize(address)' "$ID_PROXY")"

ID_ARGS="$(cast abi-encode 'constructor(address,bytes)' "$ID_IMPL"  "$IDENTITY_INIT")"
REP_ARGS="$(cast abi-encode 'constructor(address,bytes)' "$REP_IMPL" "$REPUTATION_INIT")"
VAL_ARGS="$(cast abi-encode 'constructor(address,bytes)' "$VAL_IMPL" "$VALIDATION_INIT")"

section "Implementations"
run_verify "IdentityRegistryUpgradeable"     "$ID_IMPL"  "$SOURCE_DIR/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable"
run_verify "ReputationRegistryUpgradeable"   "$REP_IMPL" "$SOURCE_DIR/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable"
run_verify "ValidationRegistryUpgradeable"   "$VAL_IMPL" "$SOURCE_DIR/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable"

section "Proxies (ERC1967Proxy)"
# Pass constructor args positionally via --constructor-args payload
run_verify "ERC1967Proxy (Identity)"         "$ID_PROXY"  "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  --constructor-args "$ID_ARGS"
run_verify "ERC1967Proxy (Reputation)"       "$REP_PROXY" "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  --constructor-args "$REP_ARGS"
run_verify "ERC1967Proxy (Validation)"       "$VAL_PROXY" "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  --constructor-args "$VAL_ARGS"

echo ""
ok "All verifications complete."