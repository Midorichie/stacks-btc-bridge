;; cross-chain-bridge.clar
;; A simple cross-chain bridge contract for Stacks-Bitcoin transfers

;; Error codes
(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_INVALID_AMOUNT u101)
(define-constant ERR_INSUFFICIENT_BALANCE u102)
(define-constant ERR_INVALID_BITCOIN_ADDRESS u103)
(define-constant ERR_INVALID_TRANSFER_ID u104)

;; Data mappings
(define-map user-balances principal uint)
(define-map bitcoin-addresses principal (string-ascii 42))
(define-map pending-transfers uint {
    sender: principal,
    btc-address: (string-ascii 42),
    amount: uint,
    status: (string-ascii 10)
})

;; Contract variables
(define-data-var transfer-counter uint u0)
(define-data-var contract-owner principal tx-sender)

;; Read-only functions
(define-read-only (get-balance (user principal))
    (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-btc-address (user principal))
    (map-get? bitcoin-addresses user)
)

(define-read-only (get-transfer (transfer-id uint))
    (map-get? pending-transfers transfer-id)
)

(define-read-only (is-valid-btc-address (btc-address (string-ascii 42)))
    ;; Basic validation - in a real implementation, you'd want more robust checks
    (let 
        (
            (len-addr (len btc-address))
            (first-char (unwrap-panic (element-at btc-address u0)))
        )
        (or 
            ;; Legacy addresses start with 1
            (is-eq first-char "1") 
            ;; P2SH addresses start with 3
            (is-eq first-char "3")
            ;; Bech32 addresses start with bc1
            (and 
                (>= len-addr u4)
                (is-eq (unwrap-panic (element-at btc-address u0)) "b")
                (is-eq (unwrap-panic (element-at btc-address u1)) "c")
                (is-eq (unwrap-panic (element-at btc-address u2)) "1")
            )
        )
    )
)

;; Public functions
(define-public (deposit)
    (let
        (
            (sender tx-sender)
            (amount (stx-get-balance tx-sender))
        )
        (if (> amount u0)
            (begin
                (try! (stx-transfer? amount sender (as-contract tx-sender)))
                (map-set user-balances sender 
                    (+ (default-to u0 (map-get? user-balances sender)) amount)
                )
                (ok amount)
            )
            (err ERR_INVALID_AMOUNT)
        )
    )
)

(define-public (register-btc-address (btc-address (string-ascii 42)))
    (begin
        ;; Validate the Bitcoin address format
        (asserts! (is-valid-btc-address btc-address) (err ERR_INVALID_BITCOIN_ADDRESS))
        (map-set bitcoin-addresses tx-sender btc-address)
        (ok true)
    )
)

(define-public (initiate-transfer (amount uint) (btc-address (string-ascii 42)))
    (let
        (
            (sender tx-sender)
            (user-balance (default-to u0 (map-get? user-balances sender)))
            (transfer-id (var-get transfer-counter))
        )
        ;; Validate inputs
        (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
        (asserts! (is-valid-btc-address btc-address) (err ERR_INVALID_BITCOIN_ADDRESS))
        (asserts! (>= user-balance amount) (err ERR_INSUFFICIENT_BALANCE))
        
        ;; Update state
        (map-set user-balances sender (- user-balance amount))
        (map-set pending-transfers transfer-id {
            sender: sender,
            btc-address: btc-address,
            amount: amount,
            status: "pending"
        })
        (var-set transfer-counter (+ transfer-id u1))
        (ok transfer-id)
    )
)

;; Admin functions
(define-public (complete-transfer (transfer-id uint))
    (let
        (
            (current-counter (var-get transfer-counter))
            (transfer (unwrap! (map-get? pending-transfers transfer-id) 
                      (err ERR_INVALID_TRANSFER_ID)))
        )
        ;; Validate inputs
        (asserts! (< transfer-id current-counter) (err ERR_INVALID_TRANSFER_ID))
        (asserts! (is-eq tx-sender (var-get contract-owner)) 
                  (err ERR_UNAUTHORIZED))
        (asserts! (is-eq (get status transfer) "pending") 
                  (err ERR_UNAUTHORIZED))

        ;; Update state
        (map-set pending-transfers transfer-id 
            (merge transfer { status: "completed" }))
        (ok true)
    )
)

(define-public (cancel-transfer (transfer-id uint))
    (let
        (
            (current-counter (var-get transfer-counter))
            (transfer (unwrap! (map-get? pending-transfers transfer-id) 
                      (err ERR_INVALID_TRANSFER_ID)))
            (sender (get sender transfer))
            (amount (get amount transfer))
            (status (get status transfer))
        )
        ;; Validate inputs
        (asserts! (< transfer-id current-counter) (err ERR_INVALID_TRANSFER_ID))
        (asserts! (or (is-eq tx-sender sender) 
                      (is-eq tx-sender (var-get contract-owner))) 
                  (err ERR_UNAUTHORIZED))
        (asserts! (is-eq status "pending") (err ERR_UNAUTHORIZED))

        ;; Update state
        (map-set pending-transfers transfer-id 
            (merge transfer { status: "cancelled" }))
        (map-set user-balances sender 
            (+ (default-to u0 (map-get? user-balances sender)) amount))
        (ok true)
    )
)
