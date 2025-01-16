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

# Function to retry a command
retry_command() {
    local max_attempts=3
    local attempt=1
    local command=$1
    local label=$2

    while [ $attempt -le $max_attempts ]; do
        print_substep "Attempt $attempt of $max_attempts: $label"
        if eval "$command"; then
            return 0
        else
            if [ $attempt -eq $max_attempts ]; then
                print_error "Failed after $max_attempts attempts"
                return 1
            fi
            print_substep "Retrying in 5 seconds..."
            sleep 5
        fi
        attempt=$((attempt + 1))
    done
}

print_step "Starting Hello World contract deployment process..."

# Check if mantrachaind is installed
if ! command -v mantrachaind &> /dev/null; then
    print_error "mantrachaind is not installed. Please install it first."
    exit 1
fi

# Setup wallet
print_step "Setting up wallet..."
if ! mantrachaind keys show wallet &> /dev/null; then
    print_substep "Creating new wallet 'wallet'..."
    print_substep "Please save your mnemonic phrase securely!"
    if ! mantrachaind keys add wallet; then
        print_error "Failed to create wallet"
        exit 1
    fi
    print_substep "Wallet created successfully!"
    print_substep "Please visit https://faucet.dukong.mantrachain.io to get testnet tokens"
    print_substep "Waiting for 10 seconds to ensure you save your mnemonic..."
    sleep 10
else
    print_substep "Wallet 'wallet' already exists"
fi

print_substep "Please ensure you have enough tokens in your wallet before proceeding."
read -p "Press Enter to continue..."

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "git is not installed. Please install it first."
    exit 1
fi

# Clone the repository
print_step "Cloning the repository..."
if [ ! -d "building-on-MANTRA-chain" ]; then
    if ! git clone https://github.com/0xmetaschool/building-on-MANTRA-chain.git; then
        print_error "Failed to clone the repository"
        exit 1
    fi
else
    print_substep "Repository already exists. Removing and cloning fresh..."
    rm -rf building-on-MANTRA-chain
    if ! git clone https://github.com/0xmetaschool/building-on-MANTRA-chain.git; then
        print_error "Failed to clone the repository"
        exit 1
    fi
fi

# Navigate to the cloned repository
cd building-on-MANTRA-chain
check_result "Failed to change to repository directory"

# Source environment variables
print_substep "Loading environment variables..."
source mantrachaind-cli.env

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Build the contract
print_step "Building contract..."
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

# Check if artifacts/hello_world.wasm exists
if [ ! -f "artifacts/hello_world.wasm" ]; then
    print_error "hello_world.wasm not found in artifacts directory"
    exit 1
fi

wait_with_message "Preparing for contract upload..." 10

# Upload contract to network with retry
print_step "Uploading contract to network..."
upload_command='RES=$(mantrachaind tx wasm store artifacts/hello_world.wasm --from wallet $TXFLAG -y --output json) && echo "$RES" | jq "."'
if ! retry_command "$upload_command" "Uploading contract"; then
    exit 1
fi

# Check for insufficient funds error
if echo "$RES" | grep -q "insufficient funds"; then
    print_error "Insufficient funds in wallet. Please get tokens from the faucet."
    exit 1
fi

wait_with_message "Waiting for transaction confirmation..." 10

# Get Code ID
print_step "Getting Code ID..."
TX_HASH=$(echo $RES | jq -r .txhash)
echo "Transaction Hash: $TX_HASH"

wait_with_message "Waiting for transaction to be mined..." 10

# Query transaction with retry
print_substep "Querying for Code ID..."
query_command='CODE_ID=$(mantrachaind query tx $TX_HASH $NODE -o json | jq -r ".events[] | select(.type == \"store_code\") | .attributes[] | select(.key == \"code_id\") | .value")'
if ! retry_command "$query_command" "Getting Code ID"; then
    exit 1
fi

if [ -z "$CODE_ID" ]; then
    print_error "Failed to get Code ID"
    exit 1
fi
echo "Code ID: $CODE_ID"

wait_with_message "Preparing to verify code..." 10

# Verify uploaded code with retry
print_step "Verifying uploaded code..."
verify_command='mantrachaind query wasm code $CODE_ID $NODE download.wasm'
if ! retry_command "$verify_command" "Downloading code for verification"; then
    exit 1
fi

if ! diff artifacts/hello_world.wasm download.wasm >/dev/null 2>&1; then
    print_error "Uploaded code verification failed"
    exit 1
fi
echo "Code verification successful!"

wait_with_message "Preparing for contract instantiation..." 10

# Instantiate contract with retry
print_step "Instantiating contract..."
instantiate_command='INST_RESULT=$(mantrachaind tx wasm instantiate $CODE_ID "{\"message\":\"Hello, World!\"}" --from wallet --label "hello_world" $TXFLAG -y --no-admin --output json) && echo "$INST_RESULT" | jq "."'
if ! retry_command "$instantiate_command" "Instantiating contract"; then
    exit 1
fi

wait_with_message "Waiting for instantiation to complete..." 10

# Get contract address with retry
print_step "Getting contract address..."
contract_command='CONTRACT=$(mantrachaind query wasm list-contract-by-code $CODE_ID $NODE --output json | jq -r ".contracts[-1]")'
if ! retry_command "$contract_command" "Getting contract address"; then
    exit 1
fi

if [ -z "$CONTRACT" ]; then
    print_error "Failed to get contract address"
    exit 1
fi
echo "Contract Address: $CONTRACT"

# Save contract address to file
echo "hello_world_contract_address = $CONTRACT" >> contractAddress.txt

wait_with_message "Preparing to query contract state..." 10

# Get contract state with retry
print_step "Getting contract state..."
state_command='STATE=$(mantrachaind query wasm contract-state all $CONTRACT $NODE --output json) && echo "$STATE" | jq "."'
if ! retry_command "$state_command" "Getting contract state"; then
    exit 1
fi

# Extract and decode the value
VALUE=$(echo $STATE | jq -r '.models[0].value')
echo "Decoded contract state:"
echo $VALUE | base64 -d

print_step "✨ Deployment completed successfully!"
echo "📝 Summary:"
echo "- Code ID: $CODE_ID"
echo "- Contract Address: $CONTRACT"
echo "- Transaction Hash: $TX_HASH"

# Save contract info for future use
echo "CODE_ID=$CODE_ID" > hello_world_contract_info
echo "CONTRACT=$CONTRACT" >> hello_world_contract_info
echo "TX_HASH=$TX_HASH" >> hello_world_contract_info

print_step "Next steps:"
echo "1. Verify your contract at: https://explorer.mantrachain.io/MANTRA-Dukong/account/$CONTRACT"
echo "2. To deploy the Todo dApp, run: ./deploy_todo.sh"
