;; BTC Shield - Risk Assessment Smart Contract
;; Initial implementation for risk assessment

;; Data Maps
(define-map risk-scores
  { asset-type: (string-ascii 20), asset-address: principal }
  {
    risk-score: uint, ;; 1-1000 scale (higher is riskier)
    last-assessment: uint,
    assessor: principal
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-invalid-score (err u405))

;; Functions

;; Submit a risk assessment (admin only)
(define-public (submit-risk-assessment 
  (asset-type (string-ascii 20)) 
  (asset-address principal) 
  (risk-score uint)
)
  (begin
    ;; Verify caller is admin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    
    ;; Verify risk score is in valid range (1-1000)
    (asserts! (and (>= risk-score u1) (<= risk-score u1000)) err-invalid-score)
    
    ;; Store the risk assessment
    (map-set risk-scores 
      {
        asset-type: asset-type,
        asset-address: asset-address
      }
      {
        risk-score: risk-score,
        last-assessment: block-height,
        assessor: tx-sender
      }
    )
    
    (ok {asset-type: asset-type, asset-address: asset-address, risk-score: risk-score})
  )
)

;; Get the risk assessment for an asset
(define-read-only (get-risk-assessment (asset-type (string-ascii 20)) (asset-address principal))
  (map-get? risk-scores {asset-type: asset-type, asset-address: asset-address})
)

;; Calculate the risk factor for premium calculation
(define-read-only (calculate-risk-factor (asset-type (string-ascii 20)) (asset-address principal))
  (let (
    (assessment (map-get? risk-scores {asset-type: asset-type, asset-address: asset-address}))
  )
    ;; If we have an assessment, use it to calculate risk factor, otherwise use default
    (if (is-some assessment)
      (let ((risk-score (get risk-score (unwrap-panic assessment))))
        ;; Convert 1-1000 score to basis points (10-1000)
        (+ u10 (/ (* risk-score u990) u1000))
      )
      ;; Default risk factor of 200 (2%)
      u200)
  )
)
