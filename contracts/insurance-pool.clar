;; BTC Shield - Insurance Pool Smart Contract
;; Insurance pool with policy creation and basic claims

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
    is-active: bool,
    is-claimed: bool
  }
)
(define-map claims 
  { claim-id: uint } 
  { 
    policy-id: uint, 
    amount: uint, 
    status: (string-ascii 10),
    verdict: bool
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-insufficient-funds (err u402))
(define-constant err-policy-expired (err u403))
(define-constant err-not-found (err u404))
(define-constant err-invalid-policy (err u405))
(define-constant err-already-claimed (err u406))
(define-constant err-insufficient-coverage (err u407))

;; ID counters
(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)

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
        is-active: true,
        is-claimed: false
      }
    )
    
    ;; Increment policy ID
    (var-set next-policy-id (+ policy-id u1))
    
    (ok policy-id)
  )
)

;; Submit a claim
(define-public (submit-claim (policy-id uint) (amount uint))
  (let (
    (policy (unwrap! (map-get? policies {policy-id: policy-id}) err-not-found))
    (claim-id (var-get next-claim-id))
    (current-block block-height)
  )
    ;; Verify policy ownership
    (asserts! (is-eq (get owner policy) tx-sender) err-unauthorized)
    ;; Verify policy is active
    (asserts! (get is-active policy) err-invalid-policy)
    ;; Verify policy has not expired
    (asserts! (<= current-block (get end-block policy)) err-policy-expired)
    ;; Verify policy has not been claimed
    (asserts! (not (get is-claimed policy)) err-already-claimed)
    ;; Verify claim amount is within coverage
    (asserts! (<= amount (get coverage-amount policy)) err-insufficient-funds)
    
    ;; Create the claim
    (map-set claims 
      {claim-id: claim-id} 
      {
        policy-id: policy-id,
        amount: amount,
        status: "pending",
        verdict: false
      }
    )
    
    ;; Increment claim ID
    (var-set next-claim-id (+ claim-id u1))
    
    (ok claim-id)
  )
)

;; Approve a claim (admin only)
(define-public (approve-claim (claim-id uint))
  (let (
    (claim (unwrap! (map-get? claims {claim-id: claim-id}) err-not-found))
    (policy-id (get policy-id claim))
    (policy (unwrap! (map-get? policies {policy-id: policy-id}) err-not-found))
    (payout-amount (get amount claim))
  )
    ;; Verify caller is admin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    
    ;; Ensure we have funds to cover the claim
    (asserts! (<= payout-amount (var-get pool-balance)) err-insufficient-funds)
    
    ;; Update claim status
    (map-set claims
      {claim-id: claim-id}
      (merge claim {
        status: "approved",
        verdict: true
      })
    )
    
    ;; Mark policy as claimed
    (map-set policies
      {policy-id: policy-id}
      (merge policy {
        is-claimed: true
      })
    )
    
    ;; Transfer funds to policy owner
    (try! (as-contract (stx-transfer? payout-amount tx-sender (get owner policy))))
    
    ;; Update pool balance
    (var-set pool-balance (- (var-get pool-balance) payout-amount))
    
    (ok claim-id)
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

;; Get claim information
(define-read-only (get-claim (claim-id uint))
  (map-get? claims {claim-id: claim-id})
)

;; Get pool stats
(define-read-only (get-pool-stats)
  {
    pool-balance: (var-get pool-balance),
    total-staked: (var-get total-staked),
    coverage-ratio: (var-get coverage-ratio)
  }
)
