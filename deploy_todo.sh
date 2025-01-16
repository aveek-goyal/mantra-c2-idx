#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}🚀 $1${NC}"
}

print_substep() {
    echo -e "${YELLOW}   ⚡ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ Error: $1${NC}"
}

# Function to wait with a message
wait_with_message() {
    local message=$1
    local seconds=$2
    echo -e "${YELLOW}⏳ $message${NC}"
    sleep $seconds
}

# Function to check command result
check_result() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

print_step "Starting Todo dApp deployment process..."

# Check if hello world contract is deployed
if [ ! -f "building-on-MANTRA-chain/hello_world_contract_info" ]; then
    print_error "Hello World contract info not found. Please run deploy_contract.sh first"
    exit 1
fi

# Check if we're in the repository
if [ ! -d "building-on-MANTRA-chain" ]; then
    print_error "Repository not found. Please run deploy_contract.sh first"
    exit 1
fi

# Navigate to the repository
cd building-on-MANTRA-chain
check_result "Failed to change to repository directory"

# Switch to boilerplate03 for frontend code
print_step "Setting up frontend boilerplate..."
git fetch origin
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "boilerplate03-local" ]; then
    git checkout boilerplate03-local 2>/dev/null || git checkout origin/boilerplate03 -b boilerplate03-local
    check_result "Failed to checkout frontend boilerplate"
    wait_with_message "Waiting for checkout to complete..." 5
else
    print_substep "Already on boilerplate03-local branch"
fi

# Switch to complete-code-v2 for complete contract code
print_step "Loading complete contract code..."
git fetch origin
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "complete-code-v2" ]; then
    git checkout complete-code-v2 2>/dev/null || git checkout origin/complete-code-v2 -b complete-code-v2
    check_result "Failed to checkout complete contract code"
    wait_with_message "Waiting for checkout to complete..." 5
else
    print_substep "Already on complete-code-v2 branch"
fi

# Change to contract directory
cd contract
check_result "Failed to change to contract directory"

# Source environment variables
print_step "Loading environment variables..."
source ./mantrachaind-cli.env

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Build the contract
print_step "Building Todo contract..."
cargo build --target wasm32-unknown-unknown --release
check_result "Contract build failed"
wait_with_message "Waiting for build to complete..." 10

# Detect system architecture for optimizer
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    OPTIMIZER_IMAGE="cosmwasm/optimizer-arm64:0.16.0"
else
    OPTIMIZER_IMAGE="cosmwasm/optimizer:0.16.0"
fi

# Optimize the contract
print_step "Optimizing contract..."
docker run --rm -v "$(pwd)":/code \
    --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
    --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
    $OPTIMIZER_IMAGE
check_result "Contract optimization failed"
wait_with_message "Waiting for optimization to complete..." 10

# Check if artifacts/to_do_list.wasm.wasm exists
if [ ! -f "./artifacts/to_do_list.wasm" ]; then
    print_error "to_do_list.wasm not found in artifacts directory"
    exit 1
fi

wait_with_message "Preparing for contract upload..." 10

# Upload contract to network
print_step "Uploading Todo contract to network..."
RES=$(mantrachaind tx wasm store artifacts/to_do_list.wasm --from wallet $TXFLAG -y --output json)
echo "Upload response:"
echo $RES | jq '.'

# Get Code ID
print_step "Getting Code ID..."
TX_HASH=$(echo $RES | jq -r .txhash)
echo "Transaction Hash: $TX_HASH"

wait_with_message "Waiting for transaction to be mined..." 10

CODE_ID=$(mantrachaind query tx $TX_HASH $NODE -o json | jq -r '.events[] | select(.type == "store_code") | .attributes[] | select(.key == "code_id") | .value')
echo "Code ID: $CODE_ID"

# Get wallet address
WALLET_ADDR=$(mantrachaind keys show -a wallet)
check_result "Failed to get wallet address"

# Instantiate contract
print_step "Instantiating Todo contract..."
INIT_MSG="{\"owner\":\"$WALLET_ADDR\"}"
INST_RESULT=$(mantrachaind tx wasm instantiate $CODE_ID "$INIT_MSG" --from wallet --label "to_do_list.wasm" $TXFLAG -y --no-admin --output json)
echo "Instantiation response:"
echo $INST_RESULT | jq '.'

wait_with_message "Waiting for instantiation to complete..." 10

# Get contract address
print_step "Getting contract address..."
CONTRACT=$(mantrachaind query wasm list-contract-by-code $CODE_ID $NODE --output json | jq -r '.contracts[-1]')
echo "Contract Address: $CONTRACT"

# Save contract info for frontend
print_step "Setting up frontend..."
cd ..
cat > interface/.env << EOL
VITE_CONTRACT_ADDRESS=$CONTRACT
EOL

# Navigate to interface directory
print_substep "Installing frontend dependencies..."
cd interface

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install Node.js and npm first."
    exit 1
fi

# Install dependencies
if ! npm install --legacy-peer-deps; then
    print_error "Failed to install frontend dependencies"
    exit 1
fi

print_step "🎉 Todo dApp deployment completed!"
echo ""
echo "To start the frontend:"
echo "1. Got to interface directory"
echo "2. And run: npm run dev"
echo ""
echo "Contract Information:"
echo "- Code ID: $CODE_ID"
echo "- Contract Address: $CONTRACT"
echo "- Chain ID: $CHAIN_ID"
echo ""
echo "Happy coding! 🚀"
