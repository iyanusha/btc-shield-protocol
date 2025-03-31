;; BTC Shield - Insurance Pool Smart Contract
;; This contract manages the insurance pool, premium collection, and coverage

;; Data Variables
(define-data-var pool-balance uint u0)
(define-data-var total-staked uint u0)
(define-data-var coverage-ratio uint u400) ;; 4x coverage ratio (400%)
(define-data-var protocol-fee uint u50) ;; 0.5% fee (in basis points)
(define-data-var minimum-coverage uint u10000000) ;; 0.1 STX minimum

;; Data Maps
(define-map insurers principal { staked-amount: uint, rewards-accumulated: uint, last-update: uint })
(define-map policies 
  { policy-id: uint } 
  { 
    owner: principal, 
    coverage-amount: uint, 
    premium-amount: uint, 
    start-block: uint, 
    end-block: uint, 
    coverage-type: (string-ascii 20),
    is-active: bool,
    is-claimed: bool
  }
)
(define-map coverage-types 
  { type-id: (string-ascii 20) } 
  { 
    base-premium: uint, 
    risk-factor: uint,
    claim-verification: principal
  }
)
(define-map claims 
  { claim-id: uint } 
  { 
    policy-id: uint, 
    amount: uint, 
    evidence: (string-ascii 128),
    status: (string-ascii 10),
    verifier: principal,
    verdict: bool
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u404))
(define-constant err-unauthorized (err u401))
(define-constant err-insufficient-funds (err u402))
(define-constant err-policy-expired (err u403))
(define-constant err-invalid-policy (err u405))
(define-constant err-already-claimed (err u406))
(define-constant err-insufficient-coverage (err u407))

;; Policy ID counter
(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)

;; Functions

;; Stake STX to become an insurer
(define-public (stake-insurance (amount uint))
  (let (
    (current-stake (default-to u0 (get staked-amount (map-get? insurers tx-sender))))
    (current-block block-height)
  )
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set insurers tx-sender {
      staked-amount: (+ current-stake amount),
      rewards-accumulated: (default-to u0 (get rewards-accumulated (map-get? insurers tx-sender))),
      last-update: current-block
    })
    (var-set total-staked (+ (var-get total-staked) amount))
    (var-set pool-balance (+ (var-get pool-balance) amount))
    (ok amount)
  )
)

;; Request policy coverage
(define-public (purchase-policy (coverage-amount uint) (coverage-type (string-ascii 20)) (duration uint))
  (let (
    (coverage-details (unwrap! (map-get? coverage-types {type-id: coverage-type}) err-not-found))
    (base-premium (get base-premium coverage-details))
    (risk-factor (get risk-factor coverage-details))
    (premium-amount (calculate-premium coverage-amount base-premium risk-factor))
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
        coverage-type: coverage-type,
        is-active: true,
        is-claimed: false
      }
    )
    
    ;; Increment policy ID
    (var-set next-policy-id (+ policy-id u1))
    
    (ok policy-id)
  )
)

;; Calculate premium based on coverage amount, base rate, and risk factor
(define-read-only (calculate-premium (coverage-amount uint) (base-premium uint) (risk-factor uint))
  (let (
    ;; Formula: (coverage * base-premium * risk-factor) / 10000
    ;; Base premium and risk factor are in basis points (100 = 1%)
    (premium (/ (* (* coverage-amount base-premium) risk-factor) u1000000))
  )
    ;; Ensure the premium is at least 1 microSTX
    (if (> premium u0) premium u1)
  )
)

;; Submit a claim
(define-public (submit-claim (policy-id uint) (amount uint) (evidence (string-ascii 128)))
  (let (
    (policy (unwrap! (map-get? policies {policy-id: policy-id}) err-not-found))
    (claim-id (var-get next-claim-id))
    (current-block block-height)
    (coverage-details (unwrap! (map-get? coverage-types {type-id: (get coverage-type policy)}) err-not-found))
    (verifier (get claim-verification coverage-details))
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
        evidence: evidence,
        status: "pending",
        verifier: verifier,
        verdict: false
      }
    )
    
    ;; Increment claim ID
    (var-set next-claim-id (+ claim-id u1))
    
    (ok claim-id)
  )
)

;; Verify a claim (called by authorized verifier)
(define-public (verify-claim (claim-id uint) (approved bool))
  (let (
    (claim (unwrap! (map-get? claims {claim-id: claim-id}) err-not-found))
    (policy-id (get policy-id claim))
    (policy (unwrap! (map-get? policies {policy-id: policy-id}) err-not-found))
    (coverage-details (unwrap! (map-get? coverage-types {type-id: (get coverage-type policy)}) err-not-found))
  )
    ;; Verify caller is authorized verifier
    (asserts! (is-eq tx-sender (get verifier claim)) err-unauthorized)
    
    ;; Update claim with verification result
    (map-set claims 
      {claim-id: claim-id} 
      (merge claim {
        status: (if approved "approved" "rejected"),
        verdict: approved
      })
    )
    
    ;; If approved, mark policy as claimed and process payout
    (if approved
      (begin
        (map-set policies 
          {policy-id: policy-id} 
          (merge policy {is-claimed: true})
        )
        (try! (process-claim-payout claim-id))
        (ok claim-id)
      )
      (ok claim-id)
    )
  )
)

;; Process claim payout (internal function)
(define-private (process-claim-payout (claim-id uint))
  (let (
    (claim (unwrap! (map-get? claims {claim-id: claim-id}) err-not-found))
    (policy (unwrap! (map-get? policies {policy-id: (get policy-id claim)}) err-not-found))
    (payout-amount (get amount claim))
  )
    ;; Ensure we have funds to cover the claim
    (asserts! (<= payout-amount (var-get pool-balance)) err-insufficient-funds)
    
    ;; Transfer funds to policy owner
    (try! (as-contract (stx-transfer? payout-amount tx-sender (get owner policy))))
    
    ;; Update pool balance
    (var-set pool-balance (- (var-get pool-balance) payout-amount))
    
    (ok claim-id)
  )
)

;; Unstake funds (for insurers)
(define-public (unstake (amount uint))
  (let (
    (insurer-data (unwrap! (map-get? insurers tx-sender) err-not-found))
    (staked-amount (get staked-amount insurer-data))
  )
    ;; Verify unstake amount
    (asserts! (<= amount staked-amount) err-insufficient-funds)
    
    ;; Verify we maintain coverage ratio after unstake
    (asserts! (>= (- (var-get total-staked) amount) (get-required-stake)) err-insufficient-coverage)
    
    ;; Transfer funds to insurer
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    ;; Update insurer data
    (map-set insurers tx-sender
      (merge insurer-data {
        staked-amount: (- staked-amount amount)
      })
    )
    
    ;; Update total staked and pool balance
    (var-set total-staked (- (var-get total-staked) amount))
    (var-set pool-balance (- (var-get pool-balance) amount))
    
    (ok amount)
  )
)

;; Calculate required stake based on active policies
(define-read-only (get-required-stake)
  (let (
    ;; In a real implementation, we would iterate through all active policies
    ;; For simplicity, we're using a static formula here
    (total-coverage-liability (* (var-get total-staked) u1)) ;; Placeholder
  )
    (/ (* total-coverage-liability (var-get coverage-ratio)) u100)
  )
)

;; Register a coverage type (admin only)
(define-public (register-coverage-type (type-id (string-ascii 20)) (base-premium uint) (risk-factor uint) (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (map-set coverage-types 
      {type-id: type-id} 
      {
        base-premium: base-premium,
        risk-factor: risk-factor,
        claim-verification: verifier
      }
    )
    (ok type-id)
  )
)

;; Read-only functions to get information

(define-read-only (get-policy (policy-id uint))
  (map-get? policies {policy-id: policy-id})
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims {claim-id: claim-id})
)

(define-read-only (get-coverage-type (type-id (string-ascii 20)))
  (map-get? coverage-types {type-id: type-id})
)

(define-read-only (get-insurer-data (address principal))
  (map-get? insurers address)
)

(define-read-only (get-pool-stats)
  {
    pool-balance: (var-get pool-balance),
    total-staked: (var-get total-staked),
    coverage-ratio: (var-get coverage-ratio),
    required-stake: (get-required-stake)
  }
)
