;; BTC Shield - Insurance Pool Smart Contract
;; Insurance pool with policy creation functionality

;; Data Variables
(define-data-var pool-balance uint u0)
(define-data-var total-staked uint u0)
(define-data-var coverage-ratio uint u400) ;; 4x coverage ratio (400%)
(define-data-var minimum-coverage uint u10000000) ;; 0.1 STX minimum

;; Data Maps
(define-map insurers principal { staked-amount: uint, rewards-accumulated: uint })
(define-map policies 
  { policy-id: uint } 
  { 
    owner: principal, 
    coverage-amount: uint, 
    premium-amount: uint, 
    start-block: uint, 
    end-block: uint, 
    is-active: bool
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-insufficient-funds (err u402))
(define-constant err-insufficient-coverage (err u407))

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
      staked-amount: (+ current-stake amount),
      rewards-accumulated: (default-to u0 (get rewards-accumulated (map-get? insurers tx-sender)))
    })
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set pool-balance (+ (var-get pool-balance) amount))
    (ok amount)
  )
)

;; Calculate premium (simple fixed percentage)
(define-read-only (calculate-premium (coverage-amount uint))
  ;; 2% premium rate
  (/ (* coverage-amount u2) u100)
)

;; Request policy coverage
(define-public (purchase-policy (coverage-amount uint) (duration uint))
  (let (
    (premium-amount (calculate-premium coverage-amount))
    (policy-id (var-get next-policy-id))
    (current-block block-height)
    (expiration-block (+ current-block duration))
  )
    ;; Verify we have enough coverage capacity
    (asserts! (>= (var-get total-staked) (/ (* coverage-amount (var-get coverage-ratio)) u100)) err-insufficient-coverage)
    ;; Verify minimum coverage amount
    (asserts! (>= coverage-amount (var-get minimum-coverage)) err-insufficient-funds)
    
    ;; Transfer premium to contract
    (try! (stx-transfer? premium-amount tx-sender (as-contract tx-sender)))
    
    ;; Update balance with premium
    (var-set pool-balance (+ (var-get pool-balance) premium-amount))
    
    ;; Create the policy
    (map-set policies 
      {policy-id: policy-id} 
      {
        owner: tx-sender,
        coverage-amount: coverage-amount,
        premium-amount: premium-amount,
        start-block: current-block,
        end-block: expiration-block,
        is-active: true
      }
    )
    
    ;; Increment policy ID
    (var-set next-policy-id (+ policy-id u1))
    
    (ok policy-id)
  )
)

;; Get insurer data
(define-read-only (get-insurer-data (address principal))
  (map-get? insurers address)
)

;; Get policy information
(define-read-only (get-policy (policy-id uint))
  (map-get? policies {policy-id: policy-id})
)

;; Get pool stats
(define-read-only (get-pool-stats)
  {
    pool-balance: (var-get pool-balance),
    total-staked: (var-get total-staked),
    coverage-ratio: (var-get coverage-ratio)
  }
)
