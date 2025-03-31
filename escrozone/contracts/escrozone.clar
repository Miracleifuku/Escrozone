;; EscroZone
;; A secure escrow smart contract for facilitating trusted transactions between buyers and sellers

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-DOESNT-EXIST (err u102))
(define-constant ERR-WRONG-STATUS (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))

;; Deal status
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-COMPLETED u2)
(define-constant STATUS-CANCELLED u3)
(define-constant STATUS-DISPUTED u4)

;; Data maps
(define-map deals
    { deal-id: uint }
    {
        seller: principal,
        buyer: principal,
        arbiter: principal,
        amount: uint,
        status: uint,
        description: (string-ascii 256)
    }
)

(define-map deal-counter
    { counter-id: (string-ascii 20) }
    { counter: uint }
)

;; SIP-010 trait
(define-trait sip-010-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
    )
)

;; Read-only functions
(define-read-only (get-deal (deal-id uint))
    (map-get? deals { deal-id: deal-id })
)

(define-read-only (get-next-deal-id)
    (default-to u0
        (get counter
            (map-get? deal-counter { counter-id: "deals" })
        )
    )
)

;; Public functions
(define-public (create-deal (buyer principal) (arbiter principal) (amount uint) (description (string-ascii 256)) (token-contract <sip-010-trait>))
    (let
        (
            (deal-id (+ (get-next-deal-id) u1))
        )
        (asserts! (is-none (get-deal deal-id)) ERR-ALREADY-EXISTS)
        (try! (contract-call? token-contract transfer
            amount
            tx-sender
            (as-contract tx-sender)
            none
        ))
        (map-set deals
            { deal-id: deal-id }
            {
                seller: tx-sender,
                buyer: buyer,
                arbiter: arbiter,
                amount: amount,
                status: STATUS-ACTIVE,
                description: description
            }
        )
        (map-set deal-counter
            { counter-id: "deals" }
            { counter: deal-id }
        )
        (ok deal-id)
    )
)

(define-public (complete-deal (deal-id uint) (token-contract <sip-010-trait>))
    (let
        (
            (deal (unwrap! (get-deal deal-id) ERR-DOESNT-EXIST))
        )
        (asserts! (is-eq (get status deal) STATUS-ACTIVE) ERR-WRONG-STATUS)
        (asserts! (or
            (is-eq tx-sender (get buyer deal))
            (is-eq tx-sender (get arbiter deal))
        ) ERR-NOT-AUTHORIZED)
        
        (try! (as-contract (contract-call? token-contract transfer
            (get amount deal)
            tx-sender
            (get seller deal)
            none
        )))
        
        (map-set deals
            { deal-id: deal-id }
            (merge deal { status: STATUS-COMPLETED })
        )
        (ok true)
    )
)

(define-public (cancel-deal (deal-id uint) (token-contract <sip-010-trait>))
    (let
        (
            (deal (unwrap! (get-deal deal-id) ERR-DOESNT-EXIST))
        )
        (asserts! (is-eq (get status deal) STATUS-ACTIVE) ERR-WRONG-STATUS)
        (asserts! (or
            (is-eq tx-sender (get seller deal))
            (is-eq tx-sender (get arbiter deal))
        ) ERR-NOT-AUTHORIZED)
        
        (try! (as-contract (contract-call? token-contract transfer
            (get amount deal)
            tx-sender
            (get seller deal)
            none
        )))
        
        (map-set deals
            { deal-id: deal-id }
            (merge deal { status: STATUS-CANCELLED })
        )
        (ok true)
    )
)

(define-public (dispute-deal (deal-id uint))
    (let
        (
            (deal (unwrap! (get-deal deal-id) ERR-DOESNT-EXIST))
        )
        (asserts! (is-eq (get status deal) STATUS-ACTIVE) ERR-WRONG-STATUS)
        (asserts! (or
            (is-eq tx-sender (get buyer deal))
            (is-eq tx-sender (get seller deal))
        ) ERR-NOT-AUTHORIZED)
        
        (map-set deals
            { deal-id: deal-id }
            (merge deal { status: STATUS-DISPUTED })
        )
        (ok true)
    )
)