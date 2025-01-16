# MANTRA Chain Todo dApp Deployment Guide

This guide will walk you through the process of deploying a Todo dApp on the MANTRA Chain using Project IDX.

## Prerequisites

- Google Account (for IDX.dev access)
- Web browser with Keplr wallet extension installed

## Setup Instructions

### 1. Project IDX Setup

1. Create an account on [IDX.dev](https://idx.dev/)
2. Sign in using your Google account
3. Import the project by clicking this link:
   [Import Project](https://idx.google.com/import?url=https://github.com/aveek-goyal/mantra-c2-idx.git)
4. Wait for the initial build to complete

### 2. Environment Setup

1. Press `F1` (or `fn + F1` on some laptops)
2. Type "Rebuild" and select "Project IDX: Rebuild Environment"
3. Repeat the rebuild process 2-3 times until you see the `.cargo` folder created
4. Navigate to the "onStart" tab in the terminal

### 3. Deploy Hello World Contract

1. Run the first deployment script:
   ```bash
   ./deploy_hello_world.sh
   ```

2. When prompted:
   - Create a new wallet
   - Get test funds from the faucet
   - Set up Keplr wallet with MANTRA Chain
   
3. Enter your keyphrase when prompted during the deployment process
4. Wait for the deployment to complete successfully

### 4. Deploy Todo dApp

1. Run the Todo dApp deployment script:
   ```bash
   ./deploy_todo.sh
   ```

2. Follow the prompts and enter your keyphrase when requested
3. Wait for the deployment to complete

### 5. Access Your dApp

Once deployment is complete:
1. Navigate to the interface directory
2. Run `npm run dev` to start the development server
3. Access your Todo dApp

## Important Notes

- Make sure to save your wallet mnemonic phrase securely
- Keep track of your contract addresses (saved in `contractAddress.txt`)
- Monitor your token balance during deployments
