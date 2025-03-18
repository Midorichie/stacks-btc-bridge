;; token-bridge.clar
;; Handles token-specific functionality for cross-chain transfers

;; Error codes
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_INVALID_AMOUNT u101)
(define-constant ERR_INSUFFICIENT_BALANCE u102)
(define-constant ERR_INVALID_TOKEN u103)
(define-constant ERR_INVALID_TRANSFER_ID u104)
(define-constant ERR_LOCKED_PERIOD u105)
(define-constant ERR_ALREADY_EXECUTED u106)
(define-constant ERR_OPERATION_FAILED u107)

;; Constants
(define-constant LOCK_PERIOD u144) ;; ~24 hours in Stacks blocks
(define-constant MAX_TRANSFER_AMOUNT u1000000000) ;; 1000 STX

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var treasury-address principal tx-sender)
(define-data-var transfer-nonce uint u0)
(define-data-var protocol-fee-rate uint u500) ;; 0.5% (denominated in basis points: 10000 = 100%)
(define-data-var emergency-shutdown bool false)

;; Data maps
(define-map supported-tokens (string-ascii 10) bool)
(define-map token-transfers uint {
    sender: principal,
    recipient: (string-ascii 42),
    token-type: (string-ascii 10),
    amount: uint,
    fee: uint,
    timestamp: uint,
    status: (string-ascii 12),
    confirmations: uint
})

(define-map trusted-validators principal uint)
(define-map transfer-signatures { transfer-id: uint, validator: principal } bool)

;; On-initialize contract
(begin
    ;; Set initial supported tokens
    (map-set supported-tokens "stx" true)
    
    ;; Add contract deployer as validator with weight 1
    (map-set trusted-validators tx-sender u1)
)

;; Read-only functions
(define-read-only (get-transfer (transfer-id uint))
    (map-get? token-transfers transfer-id)
)

(define-read-only (is-supported-token (token-type (string-ascii 10)))
    (default-to false (map-get? supported-tokens token-type))
)

(define-read-only (get-transfer-status (transfer-id uint))
    (get status (default-to 
        { 
            sender: tx-sender,
            recipient: "",
            token-type: "",
            amount: u0,
            fee: u0,
            timestamp: u0,
            status: "not-found",
            confirmations: u0
        } 
        (map-get? token-transfers transfer-id)))
)

(define-read-only (calculate-fee (amount uint))
    (/ (* amount (var-get protocol-fee-rate)) u10000)
)

(define-read-only (is-validator (validator principal))
    (is-some (map-get? trusted-validators validator))
)

(define-read-only (get-validator-weight (validator principal))
    (default-to u0 (map-get? trusted-validators validator))
)

(define-read-only (get-signature-count (transfer-id uint))
    (let 
        (
            (validator1 (var-get contract-owner))
            (validator1-weight (get-validator-weight validator1))
            (validator1-signed (default-to false (map-get? transfer-signatures 
                { transfer-id: transfer-id, validator: validator1 })))
            (count (if validator1-signed validator1-weight u0))
        )
        {
            transfer-id: transfer-id,
            count: count
        }
    )
)

(define-private (check-signature (transfer-id uint) (validator principal))
    (let
        (
            (weight (default-to u0 (map-get? trusted-validators validator)))
            (has-signed (default-to false (map-get? transfer-signatures 
                { transfer-id: transfer-id, validator: validator })))
        )
        (if has-signed
            weight
            u0
        )
    )
)

;; Public functions
(define-public (register-token (token-type (string-ascii 10)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (asserts! (not (var-get emergency-shutdown)) (err ERR_OPERATION_FAILED))
        (map-set supported-tokens token-type true)
        (ok true)
    )
)

(define-public (initiate-transfer 
    (recipient (string-ascii 42)) 
    (token-type (string-ascii 10)) 
    (amount uint))
    
    (let
        (
            (sender tx-sender)
            (current-height block-height)
            (transfer-id (var-get transfer-nonce))
            (fee (calculate-fee amount))
            (total-amount (+ amount fee))
        )
        ;; Perform validations
        (asserts! (not (var-get emergency-shutdown)) (err ERR_OPERATION_FAILED))
        (asserts! (is-supported-token token-type) (err ERR_INVALID_TOKEN))
        (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
        (asserts! (<= amount MAX_TRANSFER_AMOUNT) (err ERR_INVALID_AMOUNT))
        
        ;; Handle token transfers based on type
        (if (is-eq token-type "stx")
            ;; For STX transfers
            (begin
                (try! (stx-transfer? total-amount sender (as-contract tx-sender)))
                
                ;; Forward fee to treasury
                (try! (as-contract (stx-transfer? fee tx-sender (var-get treasury-address))))
                
                ;; Record the transfer
                (map-set token-transfers transfer-id {
                    sender: sender,
                    recipient: recipient,
                    token-type: token-type,
                    amount: amount,
                    fee: fee,
                    timestamp: current-height,
                    status: "pending",
                    confirmations: u0
                })
                
                ;; Increment nonce
                (var-set transfer-nonce (+ transfer-id u1))
                (ok transfer-id)
            )
            ;; For other tokens (not implemented yet)
            (err ERR_INVALID_TOKEN)
        )
    )
)

(define-public (confirm-transfer (transfer-id uint))
    (let
        (
            (validator tx-sender)
            (transfer (unwrap! (map-get? token-transfers transfer-id) 
                      (err ERR_INVALID_TRANSFER_ID)))
            (current-height block-height)
            (status (get status transfer))
        )
        ;; Perform validations
        (asserts! (not (var-get emergency-shutdown)) (err ERR_OPERATION_FAILED))
        (asserts! (is-validator validator) (err ERR_UNAUTHORIZED))
        (asserts! (is-eq status "pending") (err ERR_ALREADY_EXECUTED))
        
        ;; Record signature
        (map-set transfer-signatures { transfer-id: transfer-id, validator: validator } true)
        
        ;; Update confirmation count
        (map-set token-transfers transfer-id 
            (merge transfer { 
                confirmations: (+ (get confirmations transfer) (get-validator-weight validator)) 
            })
        )
        
        (ok true)
    )
)

(define-public (execute-transfer (transfer-id uint))
    (let
        (
            (transfer (unwrap! (map-get? token-transfers transfer-id) 
                      (err ERR_INVALID_TRANSFER_ID)))
            (current-height block-height)
            (status (get status transfer))
            (timestamp (get timestamp transfer))
            (confirmations (get confirmations transfer))
            (needed-confirmations u2) ;; Require at least 2 weighted confirmations
        )
        ;; Perform validations
        (asserts! (not (var-get emergency-shutdown)) (err ERR_OPERATION_FAILED))
        (asserts! (is-eq status "pending") (err ERR_ALREADY_EXECUTED))
        (asserts! (>= (- current-height timestamp) LOCK_PERIOD) (err ERR_LOCKED_PERIOD))
        (asserts! (>= confirmations needed-confirmations) (err ERR_UNAUTHORIZED))
        
        ;; Update transfer status
        (map-set token-transfers transfer-id 
            (merge transfer { status: "completed" })
        )
        
        ;; In a real implementation, this would trigger an event 
        ;; that external systems would use to execute the BTC transfer
        (ok true)
    )
)

(define-public (cancel-transfer (transfer-id uint))
    (let
        (
            (sender tx-sender)
            (transfer (unwrap! (map-get? token-transfers transfer-id) 
                      (err ERR_INVALID_TRANSFER_ID)))
            (transfer-sender (get sender transfer))
            (status (get status transfer))
            (amount (get amount transfer))
            (token-type (get token-type transfer))
        )
        ;; Perform validations
        (asserts! (or 
            (is-eq sender transfer-sender) 
            (is-eq sender (var-get contract-owner))
        ) (err ERR_UNAUTHORIZED))
        (asserts! (is-eq status "pending") (err ERR_ALREADY_EXECUTED))
        
        ;; Update transfer status
        (map-set token-transfers transfer-id 
            (merge transfer { status: "cancelled" })
        )
        
        ;; Refund tokens (only amount, not the fee)
        (if (is-eq token-type "stx")
            (as-contract (stx-transfer? amount tx-sender transfer-sender))
            (err ERR_INVALID_TOKEN)
        )
    )
)

;; Admin functions
(define-public (add-validator (validator principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (asserts! (not (var-get emergency-shutdown)) (err ERR_OPERATION_FAILED))
        (asserts! (> weight u0) (err ERR_INVALID_AMOUNT))
        (map-set trusted-validators validator weight)
        (ok true)
    )
)

(define-public (remove-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (asserts! (not (is-eq validator (var-get contract-owner))) (err ERR_UNAUTHORIZED))
        (map-delete trusted-validators validator)
        (ok true)
    )
)

(define-public (set-treasury (new-treasury principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (var-set treasury-address new-treasury)
        (ok true)
    )
)

(define-public (set-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (asserts! (<= new-rate u1000) (err ERR_INVALID_AMOUNT)) ;; Max fee is 10%
        (var-set protocol-fee-rate new-rate)
        (ok true)
    )
)

(define-public (emergency-toggle)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (var-set emergency-shutdown (not (var-get emergency-shutdown)))
        (ok (var-get emergency-shutdown))
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
        (var-set contract-owner new-owner)
        (ok true)
    )
)
