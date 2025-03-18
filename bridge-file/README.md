# Stacks-Bitcoin Cross-Chain Bridge

This project implements a secure cross-chain asset transfer bridge between Stacks and Bitcoin blockchains.

## Overview

The bridge system consists of two main contracts:

1. **cross-chain-bridge.clar**: Basic bridge functionality for STX transfers
2. **token-bridge.clar**: Enhanced token bridge with multi-validator security and additional features

Together, these contracts allow users to:
- Deposit STX or other tokens into the bridge
- Register Bitcoin addresses for transfers
- Initiate cross-chain transfers with enhanced security
- Use a multi-signature validation system for transfers
- Apply time locks and confirmation thresholds for transfers

## Security Features

- **Multi-validator consensus**: Requires multiple validators to confirm transfers
- **Time-locked transfers**: Enforces waiting periods before execution
- **Emergency shutdown**: Allows pausing the bridge in case of detected vulnerabilities
- **Fee mechanism**: Includes protocol fees to prevent spam attacks
- **Transfer limits**: Sets maximum limits on individual transfers
- **Admin controls**: Provides owner-only functions with proper authorization checks

## Setup

### Prerequisites
- Clarinet (Stacks development tool)
- Git

### Installation
```bash
# Clone the repository
git clone https://github.com/yourusername/stacks-btc-bridge.git
cd stacks-btc-bridge

# Install dependencies
npm install
```

### Development
```bash
# Run tests
clarinet test

# Check contract
clarinet check
```

## Contract Functions

### Token Bridge Functions

#### User Functions
- `initiate-transfer(recipient, token-type, amount)`: Start a cross-chain transfer
- `cancel-transfer(transfer-id)`: Cancel a pending transfer

#### Validator Functions
- `confirm-transfer(transfer-id)`: Sign off on a transfer as a validator
- `execute-transfer(transfer-id)`: Execute a transfer after requirements are met

#### Admin Functions
- `register-token(token-type)`: Add support for a new token type
- `add-validator(validator, weight)`: Add a new validator with specified weight
- `remove-validator(validator)`: Remove a validator
- `set-treasury(new-treasury)`: Update the treasury address
- `set-fee-rate(new-rate)`: Update the protocol fee rate
- `emergency-toggle()`: Enable/disable emergency shutdown
- `transfer-ownership(new-owner)`: Transfer contract ownership

### Basic Bridge Functions

- `deposit()`: Deposit STX tokens into the bridge
- `register-btc-address(btc-address)`: Register a Bitcoin address
- `initiate-transfer(amount, btc-address)`: Initiate a transfer to Bitcoin
- `complete-transfer(transfer-id)`: Mark a transfer as completed
- `cancel-transfer(transfer-id)`: Cancel a pending transfer

## Security Considerations

While this implementation includes several security features, in a production environment consider:
- Adding additional validation for Bitcoin addresses
- Implementing Bitcoin SPV proofs for verification
- Adding more robust error handling
- Using formal verification for critical contract logic
- Implementing a governance system for parameter updates
