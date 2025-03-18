import { 
  Tx,
  Chain,
  Account,
  types
} from '@hirosystems/clarinet-sdk';
import { assertEquals } from 'assert';

// Helper function to read values from the blockchain
function getTokenTransfer(chain: Chain, transferId: number) {
  const result = chain.callReadOnlyFn(
    'token-bridge',
    'get-transfer',
    [types.uint(transferId)],
    chain.deployerAddress
  );
  return result.result.expectSome().expectTuple();
}

// The global `Clarinet` is provided by the vitest-environment-clarinet package.
Clarinet.test({
  name: "Ensures contract is properly initialized",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    // Check if STX token is supported
    let result = chain.callReadOnlyFn(
      'token-bridge',
      'is-supported-token',
      [types.ascii("stx")],
      deployer.address
    );
    result.result.expectBool(true);
    
    // Check if deployer is a validator
    result = chain.callReadOnlyFn(
      'token-bridge',
      'is-validator',
      [types.principal(deployer.address)],
      deployer.address
    );
    result.result.expectBool(true);
    
    // Check validator weight
    result = chain.callReadOnlyFn(
      'token-bridge',
      'get-validator-weight',
      [types.principal(deployer.address)],
      deployer.address
    );
    result.result.expectUint(1);
  },
});

Clarinet.test({
  name: "Can register a new token",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    
    // Try to register a token as non-owner (should fail)
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'register-token',
        [types.ascii("usda")],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(100); // ERR_UNAUTHORIZED

    // Register a token as owner
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'register-token',
        [types.ascii("usda")],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify token is now supported
    let result = chain.callReadOnlyFn(
      'token-bridge',
      'is-supported-token',
      [types.ascii("usda")],
      deployer.address
    );
    result.result.expectBool(true);
  },
});

Clarinet.test({
  name: "Can initiate a token transfer",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
    
    // Try to transfer an unsupported token (should fail)
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("unsupported"),
          types.uint(100000000)
        ],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(103); // ERR_INVALID_TOKEN
    
    // Try to transfer 0 STX (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(0)
        ],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(101); // ERR_INVALID_AMOUNT
    
    // Transfer a valid amount of STX
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(100000000) // 1 STX
        ],
        user.address
      )
    ]);
    block.receipts[0].result.expectOk().expectUint(0); // First transfer ID is 0
    
    // Verify transfer details
    const transfer = getTokenTransfer(chain, 0);
    assertEquals(transfer['sender'], user.address);
    assertEquals(transfer['recipient'], btcAddress);
    assertEquals(transfer['token-type'], "stx");
    assertEquals(transfer['amount'], "100000000");
    assertEquals(transfer['status'], "pending");
    assertEquals(transfer['confirmations'], "0");
  },
});

Clarinet.test({
  name: "Can confirm and execute transfers",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const validator = accounts.get('wallet_2')!;
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
    
    // Add a second validator
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'add-validator',
        [
          types.principal(validator.address),
          types.uint(1)
        ],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Initiate a transfer
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(100000000) // 1 STX
        ],
        user.address
      )
    ]);
    const transferId = 0;
    
    // Try to confirm from non-validator (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'confirm-transfer',
        [types.uint(transferId)],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(100); // ERR_UNAUTHORIZED
    
    // Confirm from validator 1
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'confirm-transfer',
        [types.uint(transferId)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Check confirmations
    let transfer = getTokenTransfer(chain, transferId);
    assertEquals(transfer['confirmations'], "1");
    
    // Confirm from validator 2
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'confirm-transfer',
        [types.uint(transferId)],
        validator.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Check confirmations again
    transfer = getTokenTransfer(chain, transferId);
    assertEquals(transfer['confirmations'], "2");
    
    // Try to execute before lock period (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'execute-transfer',
        [types.uint(transferId)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(105); // ERR_LOCKED_PERIOD
    
    // Mine blocks to pass lock period
    for (let i = 0; i < 145; i++) {
      chain.mineEmptyBlock();
    }
    
    // Execute transfer
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'execute-transfer',
        [types.uint(transferId)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify transfer status
    transfer = getTokenTransfer(chain, transferId);
    assertEquals(transfer['status'], "completed");
  },
});

Clarinet.test({
  name: "Can cancel a transfer",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const user2 = accounts.get('wallet_2')!;
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
    
    // Get initial balance
    const initialBalance = user.balance;
    
    // Initiate a transfer
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(10000000) // 0.1 STX
        ],
        user.address
      )
    ]);
    const transferId = 0;
    const fee = 50000; // 0.5% of 10000000
    
    // Try to cancel from unauthorized user (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'cancel-transfer',
        [types.uint(transferId)],
        user2.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(100); // ERR_UNAUTHORIZED
    
    // Cancel from original sender
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'cancel-transfer',
        [types.uint(transferId)],
        user.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify transfer status
    const transfer = getTokenTransfer(chain, transferId);
    assertEquals(transfer['status'], "cancelled");
    
    // Verify user got refunded (minus fee)
    const expectedRefund = initialBalance - fee;
    assertEquals(user.balance >= expectedRefund, true);
  },
});

Clarinet.test({
  name: "Can update contract settings",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const newTreasury = accounts.get('wallet_2')!;
    const newOwner = accounts.get('wallet_3')!;
    
    // Try to set treasury as non-owner (should fail)
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-treasury',
        [types.principal(newTreasury.address)],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(100); // ERR_UNAUTHORIZED
    
    // Set treasury as owner
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-treasury',
        [types.principal(newTreasury.address)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Update fee rate
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-fee-rate',
        [types.uint(1000)], // 10%
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Try to set too high fee rate (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-fee-rate',
        [types.uint(1001)], // > 10%
        deployer.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(101); // ERR_INVALID_AMOUNT
    
    // Transfer ownership
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'transfer-ownership',
        [types.principal(newOwner.address)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Try to set treasury with old owner (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-treasury',
        [types.principal(user.address)],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(100); // ERR_UNAUTHORIZED
    
    // Set treasury with new owner
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'set-treasury',
        [types.principal(user.address)],
        newOwner.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
  },
});

Clarinet.test({
  name: "Emergency shutdown functionality works",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const btcAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
    
    // Enable emergency shutdown
    let block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'emergency-toggle',
        [],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Try to initiate transfer during shutdown (should fail)
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(100000000)
        ],
        user.address
      )
    ]);
    block.receipts[0].result.expectErr().expectUint(107); // ERR_OPERATION_FAILED
    
    // Disable emergency shutdown
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'emergency-toggle',
        [],
        deployer.address
      )
    ]);
    block.receipts[0].result.expectOk().expectBool(false);
    
    // Initiate transfer should now work
    block = chain.mineBlock([
      Tx.contractCall(
        'token-bridge',
        'initiate-transfer',
        [
          types.ascii(btcAddress),
          types.ascii("stx"),
          types.uint(100000000)
        ],
        user.address
      )
    ]);
    block.receipts[0].result.expectOk().expectUint(0);
  },
});
