;; BTC Shield - Insurance Pool Smart Contract
;; Basic structure for insurance pool management

;; Data Variables
(define-data-var pool-balance uint u0)
(define-data-var total-staked uint u0)

;; Data Maps
(define-map insurers principal { staked-amount: uint })
(define-map policies 
  { policy-id: uint } 
  { 
    owner: principal, 
    coverage-amount: uint, 
    premium-amount: uint, 
    is-active: bool
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-insufficient-funds (err u402))

;; Policy ID counter
(define-data-var next-policy-id uint u1)

;; Functions

;; Stake STX to become an insurer
(define-public (stake-insurance (amount uint))
  (let (
    (current-stake (default-to u0 (get staked-amount (map-get? insurers tx-sender))))
  )
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set insurers tx-sender {
      staked-amount: (+ current-stake amount)
    })
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set pool-balance (+ (var-get pool-balance) amount))
    (ok amount)
  )
)

;; Get insurer data
(define-read-only (get-insurer-data (address principal))
  (map-get? insurers address)
)

;; Get pool stats
(define-read-only (get-pool-stats)
  {
    pool-balance: (var-get pool-balance),
    total-staked: (var-get total-staked)
  }
)
