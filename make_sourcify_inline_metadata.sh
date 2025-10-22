#!/usr/bin/env bash
set -euo pipefail

# make_sourcify_inline_metadata.sh
# Generate inline metadata.json bundles for HashScan/Sourcify verification:
# - IdentityRegistryUpgradeable implementation
# - ReputationRegistryUpgradeable implementation
# - ValidationRegistryUpgradeable implementation
# - ERC1967Proxy (one metadata.json usable for all three proxies)
#
# It also writes a MANIFEST.txt with exact addresses and proxy constructor args to paste into the UI.
#
# Addresses (optional but recommended; if omitted, we still build metadata files):
#   Export or pass flags for:
#     ID_IMPL, REP_IMPL, VAL_IMPL, ID_PROXY, REP_PROXY, VAL_PROXY
#
# Usage examples:
#   export ID_IMPL=0x... REP_IMPL=0x... VAL_IMPL=0x... ID_PROXY=0x... REP_PROXY=0x... VAL_PROXY=0x...
#   export HEDERA_RPC_URL=https://testnet.hashio.io/api   # optional, for sanity notes only
#   ./make_sourcify_inline_metadata.sh
#
# Or with flags:
#   ./make_sourcify_inline_metadata.sh \
#     --id-impl 0x... --rep-impl 0x... --val-impl 0x... \
#     --id-proxy 0x... --rep-proxy 0x... --val-proxy 0x...
#
# Output:
#   verify-bundles/
#     identity-impl/metadata.json
#     reputation-impl/metadata.json
#     validation-impl/metadata.json
#     proxy/metadata.json
#     MANIFEST.txt
#
# Requirements: forge, jq, cast, xxd

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

need forge
need jq
need cast
need xxd

# Addresses (optional: script works without them, but manifest is richer with them)
ID_IMPL="${ID_IMPL:-}"
REP_IMPL="${REP_IMPL:-}"
VAL_IMPL="${VAL_IMPL:-}"
ID_PROXY="${ID_PROXY:-}"
REP_PROXY="${REP_PROXY:-}"
VAL_PROXY="${VAL_PROXY:-}"

# FQCNs (override if your paths differ)
FQCN_ID="${FQCN_ID:-src/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable}"
FQCN_REP="${FQCN_REP:-src/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable}"
FQCN_VAL="${FQCN_VAL:-src/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable}"

# Optional RPC URL (for manifest note only)
RPC_URL="${HEDERA_RPC_URL:-}"

# Parse flags
while [ $# -gt 0 ]; do
  case "$1" in
    --id-impl) ID_IMPL="${2:-}"; shift 2 ;;
    --rep-impl) REP_IMPL="${2:-}"; shift 2 ;;
    --val-impl) VAL_IMPL="${2:-}"; shift 2 ;;
    --id-proxy) ID_PROXY="${2:-}"; shift 2 ;;
    --rep-proxy) REP_PROXY="${2:-}"; shift 2 ;;
    --val-proxy) VAL_PROXY="${2:-}"; shift 2 ;;
    --fqcn-id)  FQCN_ID="${2:-}"; shift 2 ;;
    --fqcn-rep) FQCN_REP="${2:-}"; shift 2 ;;
    --fqcn-val) FQCN_VAL="${2:-}"; shift 2 ;;
    --rpc-url)  RPC_URL="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Generate HashScan/Sourcify verification bundles (inline metadata + manifest) for all deployed contracts.

Optional environment variables or flags:
  Addresses:
    ID_IMPL, REP_IMPL, VAL_IMPL, ID_PROXY, REP_PROXY, VAL_PROXY
    or flags: --id-impl --rep-impl --val-impl --id-proxy --rep-proxy --val-proxy

FQCN overrides:
  --fqcn-id  "src/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable"
  --fqcn-rep "src/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable"
  --fqcn-val "src/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable"

RPC (note only):
  --rpc-url  https://testnet.hashio.io/api   (or export HEDERA_RPC_URL)

Examples:
  export ID_IMPL=0x... REP_IMPL=0x... VAL_IMPL=0x... ID_PROXY=0x... REP_PROXY=0x... VAL_PROXY=0x...
  ./make_sourcify_inline_metadata.sh
EOF
      exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

OUT_BASE="verify-bundles"
mkdir -p "$OUT_BASE"

# Helpers
trim_end_slash() { local s="$1"; while [ "${s%/}" != "$s" ]; do s="${s%/}"; done; printf "%s" "$s"; }

resolve_with_remaps() {
  # $1 = source key path from metadata; echo resolved local file path if found
  local key="$1" k="$1" cand rest
  # Load remappings (longest first) lazily once
  if [ -z "${__REMAPPING_LOADED:-}" ]; then
    __REMAPPING_FILE="$(mktemp)"
    if forge remappings >/dev/null 2>&1; then
      forge remappings | awk -F= 'NF==2{print length($1) "\t" $0}' | sort -rn | cut -f2- > "$__REMAPPING_FILE"
    else
      : > "$__REMAPPING_FILE"
    fi
    __REMAPPING_LOADED=1
  fi

  case "$k" in @*) cand="node_modules/$k"; [ -f "$cand" ] && { echo "$cand"; return 0; };; esac
  if [ -s "$__REMAPPING_FILE" ]; then
    while IFS= read -r line; do
      local from="${line%%=*}" to="${line#*=}"
      from="$(trim_end_slash "$from")"; to="$(trim_end_slash "$to")"
      if [ "$k" = "$from" ]; then cand="$to"; [ -f "$cand" ] && { echo "$cand"; return 0; }; fi
      case "$k" in "$from"/*)
        rest="${k#"$from"/}"
        cand="$to/$rest"; [ -f "$cand" ] && { echo "$cand"; return 0; }
        ;;
      esac
    done < "$__REMAPPING_FILE"
  fi
  cand="$k"; [ -f "$cand" ] && { echo "$cand"; return 0; }
  for root in src contracts lib node_modules; do
    cand="$root/$k"; [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  case "$k" in
    */contracts/*)
      rest="${k#*/contracts/}"
      for root in contracts src; do cand="$root/$rest"; [ -f "$cand" ] && { echo "$cand"; return 0; }; done ;;
  esac
  case "$k" in
    */src/*)
      rest="${k#*/src/}"
      for root in src contracts; do cand="$root/$rest"; [ -f "$cand" ] && { echo "$cand"; return 0; }; done ;;
  esac
  return 1
}

keccak_file() {
  local f="$1" hex
  hex="$(xxd -p -c 99999999 "$f" | tr -d '\n')"
  cast keccak "0x$hex"
}

inline_sources_into_metadata() {
  # $1 = metadata.json path; inlines contents and verifies keccak if present
  local metadata="$1"
  jq -e '.compiler and .language and .sources' "$metadata" >/dev/null 2>&1 || die "Invalid metadata: $metadata"

  local keys; keys="$(mktemp)"
  jq -r '.sources | keys[]' "$metadata" > "$keys"
  [ -s "$keys" ] || die "metadata.sources is empty in $metadata"

  local missing=0 mism=0
  # shellcheck disable=SC2162
  while IFS= read key; do
    key="${key%$'\r'}"
    local has_embedded meta_k calc_k
    has_embedded="$(jq -r --arg k "$key" '(.sources[$k].content // empty) | tostring' "$metadata")"
    meta_k="$(jq -r --arg k "$key" '.sources[$k].keccak256 // empty' "$metadata")"
    calc_k=""

    if [ -n "$has_embedded" ] && [ "$has_embedded" != "null" ]; then
      local tmpc; tmpc="$(mktemp)"
      jq -r --arg k "$key" '.sources[$k].content' "$metadata" > "$tmpc"
      calc_k="$(keccak_file "$tmpc")"
      rm -f "$tmpc"
    else
      local localp
      if ! localp="$(resolve_with_remaps "$key")"; then
        echo "  ! Missing source on disk: $key"
        missing=$((missing+1))
        continue
      fi
      local tmp; tmp="$(mktemp)"
      jq --arg k "$key" --rawfile c "$localp" '(.sources[$k].content = $c) | (.sources[$k] |= (del(.urls)))' "$metadata" > "$tmp" && mv "$tmp" "$metadata"
      calc_k="$(keccak_file "$localp")"
    fi

    if [ -n "$meta_k" ] && [ "$meta_k" != "null" ]; then
      meta_k="$(echo "$meta_k" | tr 'A-F' 'a-f')"
      calc_k="$(echo "$calc_k" | tr 'A-F' 'a-f')"
      if [ "$meta_k" != "$calc_k" ]; then
        echo "  ! Hash mismatch for $key"
        mism=$((mism+1))
      fi
    fi

    local tmp; tmp="$(mktemp)"
    jq --arg k "$key" '(.sources[$k] |= (del(.urls)))' "$metadata" > "$tmp" && mv "$tmp" "$metadata"
  done < "$keys"

  rm -f "$keys"
  if [ "$missing" -gt 0 ] || [ "$mism" -gt 0 ]; then
    echo "  -> WARN: $missing missing, $mism mismatched source(s)"
  else
    echo "  -> OK"
  fi
}

build_inline_metadata_from_fqcn() {
  # $1 = FQCN, $2 = outdir
  local fqcn="$1" outdir="$2"
  mkdir -p "$outdir"
  local metadata="$outdir/metadata.json"
  echo "• Building metadata for $fqcn -> $metadata"
  forge inspect "$fqcn" metadata | jq . > "$metadata" || die "forge inspect failed for $fqcn"
  inline_sources_into_metadata "$metadata"
}

build_inline_metadata_from_artifact() {
  # Build metadata.json for a contract by extracting metadata from Foundry artifact JSON
  # $1 = source key path (from metadata.sources), $2 = ContractName, $3 = outdir
  local source_key="$1" name="$2" outdir="$3"
  mkdir -p "$outdir"
  local metadata="$outdir/metadata.json"

  # Try the canonical artifact location first
  local candidate="out/$source_key/$name.json"
  if [ ! -f "$candidate" ]; then
    # Search artifacts with matching name and ensure sourcePath matches source_key
    candidate="$(find out -type f -name "$name.json" 2>/dev/null | while read -r f; do
      sp="$(jq -r '.sourcePath // empty' "$f" 2>/dev/null || true)"
      if [ -n "$sp" ] && [ "$sp" = "$source_key" ]; then echo "$f"; break; fi
    done)"
    # Fallback: if still empty, pick the first one under the expected filename folder
    if [ -z "$candidate" ]; then
      candidate="$(find "out" -path "out/*/ERC1967Proxy.sol/$name.json" -type f 2>/dev/null | head -n1 || true)"
    fi
  fi

  [ -n "$candidate" ] && [ -f "$candidate" ] || die "Could not locate artifact for $name at source '$source_key'"

  # Extract 'metadata' string or accept entire file if it already looks like solc metadata
  if jq -e '.compiler and .language and .sources' "$candidate" >/dev/null 2>&1; then
    cp -f "$candidate" "$metadata"
  else
    jq -r '.metadata' "$candidate" | jq . > "$metadata"
  fi

  echo "• Building metadata from artifact $candidate -> $metadata"
  inline_sources_into_metadata "$metadata"
}

# Discover the exact ERC1967Proxy source key used by your build (avoid duplicate-name ambiguity)
discover_proxy_source_key() {
  # Use Identity metadata (compiled in your project) to find the path of ERC1967Proxy.sol actually used
  forge inspect "$FQCN_ID" metadata \
    | jq -r '.sources | keys[] | select(endswith("ERC1967Proxy.sol"))' \
    | head -n1
}

# Compute proxy initializer calldatas (works even if addresses not provided; will be empty where needed)
ID_INIT="$(cast calldata 'initialize()')"
REP_INIT=""
VAL_INIT=""
if [ -n "$ID_PROXY" ]; then
  REP_INIT="$(cast calldata 'initialize(address)' "$ID_PROXY")"
  VAL_INIT="$(cast calldata 'initialize(address)' "$ID_PROXY")"
fi

echo "== Generating inline metadata bundles =="

# Implementations via FQCN (forge inspect)
build_inline_metadata_from_fqcn "$FQCN_ID"  "$OUT_BASE/identity-impl"
build_inline_metadata_from_fqcn "$FQCN_REP" "$OUT_BASE/reputation-impl"
build_inline_metadata_from_fqcn "$FQCN_VAL" "$OUT_BASE/validation-impl"

# Proxy via artifact referenced by Identity metadata (avoids "Multiple contracts found")
PROXY_SOURCE_KEY="$(discover_proxy_source_key || true)"
if [ -z "$PROXY_SOURCE_KEY" ]; then
  # Fallback to common OZ location if not found (rare)
  PROXY_SOURCE_KEY="lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol"
  echo "• WARN: Could not discover proxy source from metadata. Falling back to: $PROXY_SOURCE_KEY"
else
  echo "• Proxy source key discovered: $PROXY_SOURCE_KEY"
fi
build_inline_metadata_from_artifact "$PROXY_SOURCE_KEY" "ERC1967Proxy" "$OUT_BASE/proxy"

# Write MANIFEST
MANIFEST="$OUT_BASE/MANIFEST.txt"
{
  echo "HashScan Verify Upload Guide"
  echo "============================"
  echo ""
  echo "Upload files at https://verify.hashscan.io/"
  echo ""
  echo "Implementations:"
  echo "- IdentityRegistryUpgradeable"
  echo "  File: $OUT_BASE/identity-impl/metadata.json"
  [ -n "$ID_IMPL" ] && echo "  Address: $ID_IMPL" || echo "  Address: <set ID_IMPL>"
  echo ""
  echo "- ReputationRegistryUpgradeable"
  echo "  File: $OUT_BASE/reputation-impl/metadata.json"
  [ -n "$REP_IMPL" ] && echo "  Address: $REP_IMPL" || echo "  Address: <set REP_IMPL>"
  echo ""
  echo "- ValidationRegistryUpgradeable"
  echo "  File: $OUT_BASE/validation-impl/metadata.json"
  [ -n "$VAL_IMPL" ] && echo "  Address: $VAL_IMPL" || echo "  Address: <set VAL_IMPL>"
  echo ""
  echo "Proxies (same metadata.json; provide constructor args):"
  echo "- ERC1967Proxy (Identity)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$ID_PROXY" ] && echo "  Address: $ID_PROXY" || echo "  Address: <set ID_PROXY>"
  echo "  Constructor args:"
  [ -n "$ID_IMPL" ] && echo "    _logic = $ID_IMPL" || echo "    _logic = <ID_IMPL>"
  echo "    _data  = $ID_INIT"
  echo ""
  echo "- ERC1967Proxy (Reputation)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$REP_PROXY" ] && echo "  Address: $REP_PROXY" || echo "  Address: <set REP_PROXY>"
  echo "  Constructor args:"
  [ -n "$REP_IMPL" ] && echo "    _logic = $REP_IMPL" || echo "    _logic = <REP_IMPL>"
  [ -n "$REP_INIT" ] && echo "    _data  = $REP_INIT" || echo "    _data  = <cast calldata 'initialize(address)' ID_PROXY>"
  echo ""
  echo "- ERC1967Proxy (Validation)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$VAL_PROXY" ] && echo "  Address: $VAL_PROXY" || echo "  Address: <set VAL_PROXY>"
  echo "  Constructor args:"
  [ -n "$VAL_IMPL" ] && echo "    _logic = $VAL_IMPL" || echo "    _logic = <VAL_IMPL>"
  [ -n "$VAL_INIT" ] && echo "    _data  = $VAL_INIT" || echo "    _data  = <cast calldata 'initialize(address)' ID_PROXY>"
  echo ""
  echo "Notes:"
  echo "- Each metadata.json embeds all sources; upload just that single file."
  [ -n "$RPC_URL" ] && echo "- Network RPC for sanity purposes: $RPC_URL"
} > "$MANIFEST"

echo ""
echo "Done."
echo "Bundles and manifest are in: $OUT_BASE"
echo "Open $MANIFEST for copy/paste-ready instructions."