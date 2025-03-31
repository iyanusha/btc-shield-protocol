;; BTC Shield - Risk Assessment Smart Contract
;; Enhanced with risk models and specialized areas

;; Data Maps
(define-map risk-oracles
  principal
  {
    oracle-name: (string-ascii 50),
    reliability-score: uint,
    specialized-areas: (list 5 (string-ascii 20)),
    is-active: bool
  }
)

(define-map risk-scores
  { asset-type: (string-ascii 20), asset-address: principal }
  {
    risk-score: uint, ;; 1-1000 scale (higher is riskier)
    last-assessment: uint,
    assessor: principal,
    confidence: uint ;; 1-100 scale
  }
)

(define-map risk-models
  (string-ascii 20)
  {
    base-risk: uint,
    volatility-weight: uint,
    liquidity-weight: uint,
    code-audit-weight: uint,
    age-weight: uint
  }
)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-not-found (err u404))
(define-constant err-invalid-score (err u405))
(define-constant err-invalid-confidence (err u406))

;; Variables
(define-data-var min-confidence-threshold uint u60)
(define-data-var oracle-consensus-required uint u3)

;; Functions

;; Register as a risk oracle
(define-public (register-oracle (oracle-name (string-ascii 50)) (specialized-areas (list 5 (string-ascii 20))))
  (begin
    ;; In a production system, we would verify the oracle's identity and credentials
    (map-set risk-oracles tx-sender {
      oracle-name: oracle-name,
      reliability-score: u500, ;; Starting at 50% reliability
      specialized-areas: specialized-areas,
      is-active: true
    })
    (ok tx-sender)
  )
)

;; Submit a risk assessment for an asset
(define-public (submit-risk-assessment 
  (asset-type (string-ascii 20)) 
  (asset-address principal) 
  (risk-score uint) 
  (confidence uint)
)
  (let (
    (oracle (unwrap! (map-get? risk-oracles tx-sender) err-unauthorized))
    (current-block block-height)
  )
    ;; Verify oracle is active
    (asserts! (get is-active oracle) err-unauthorized)
    
    ;; Verify risk score is in valid range (1-1000)
    (asserts! (and (>= risk-score u1) (<= risk-score u1000)) err-invalid-score)
    
    ;; Verify confidence is in valid range (1-100)
    (asserts! (and (>= confidence u1) (<= confidence u100)) err-invalid-confidence)
    
    ;; Store the risk assessment
    (map-set risk-scores 
      {
        asset-type: asset-type,
        asset-address: asset-address
      }
      {
        risk-score: risk-score,
        last-assessment: current-block,
        assessor: tx-sender,
        confidence: confidence
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
    (model (map-get? risk-models asset-type))
  )
    ;; If we have both an assessment and a model, calculate detailed risk factor
    (if (and (is-some assessment) (is-some model))
      (calculate-detailed-risk-factor (unwrap-panic assessment) (unwrap-panic model))
      ;; Otherwise use a default risk factor of 200 (2%)
      u200)
  )
)

;; Calculate detailed risk factor based on assessment and model
(define-private (calculate-detailed-risk-factor (assessment {risk-score: uint, last-assessment: uint, assessor: principal, confidence: uint}) (model {base-risk: uint, volatility-weight: uint, liquidity-weight: uint, code-audit-weight: uint, age-weight: uint}))
  (let (
    (risk-score (get risk-score assessment))
    (confidence (get confidence assessment))
    (base-risk (get base-risk model))
    
    ;; Calculate weighted risk
    (weighted-risk (* risk-score (/ confidence u100)))
    
    ;; Calculate final risk factor (base + weighted risk)
    (risk-factor (+ base-risk (/ weighted-risk u10)))
  )
    ;; Ensure risk factor is at least 50 (0.5%)
    (if (< risk-factor u50) u50 risk-factor)
  )
)

;; Register a risk model for an asset type (admin only)
(define-public (register-risk-model 
  (asset-type (string-ascii 20)) 
  (base-risk uint) 
  (volatility-weight uint) 
  (liquidity-weight uint) 
  (code-audit-weight uint) 
  (age-weight uint)
)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (map-set risk-models 
      asset-type
      {
        base-risk: base-risk,
        volatility-weight: volatility-weight,
        liquidity-weight: liquidity-weight,
        code-audit-weight: code-audit-weight,
        age-weight: age-weight
      }
    )
    (ok asset-type)
  )
)

;; Update oracle reliability score (admin only)
(define-public (update-oracle-reliability (oracle principal) (reliability-score uint))
  (let (
    (oracle-data (unwrap! (map-get? risk-oracles oracle) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= reliability-score u1000) err-invalid-score)
    
    (map-set risk-oracles 
      oracle
      (merge oracle-data {reliability-score: reliability-score})
    )
    (ok oracle)
  )
)

;; Set minimum confidence threshold (admin only)
(define-public (set-min-confidence-threshold (threshold uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= threshold u100) err-invalid-confidence)
    (var-set min-confidence-threshold threshold)
    (ok threshold)
  )
)

;; Get oracle information
(define-read-only (get-oracle-info (oracle principal))
  (map-get? risk-oracles oracle)
)

;; Get risk model for asset type
(define-read-only (get-risk-model (asset-type (string-ascii 20)))
  (map-get? risk-models asset-type)
)

;; Check if an oracle is authorized for a specific asset type
(define-read-only (is-oracle-authorized (oracle principal) (asset-type (string-ascii 20)))
  (let (
    (oracle-data (map-get? risk-oracles oracle))
  )
    (if (is-some oracle-data)
      (let (
        (oracle-info (unwrap-panic oracle-data))
        (specialized-areas (get specialized-areas oracle-info))
      )
        (and 
          (get is-active oracle-info)
          (>= (get reliability-score oracle-info) u300) 
          (is-some (index-of specialized-areas asset-type))
        )
      )
      false
    )
  )
)

;; Get average risk score for an asset type
(define-read-only (get-average-risk-score (asset-type (string-ascii 20)))
  ;; In a real implementation, we would calculate the average across multiple assessments
  ;; For simplicity in this example, we'll return a default value
  u500
)

;; Get total number of registered oracles
(define-read-only (get-oracle-count)
  ;; In a real implementation, we would count all oracles
  ;; For simplicity, we return a placeholder
  u5
)

;; Set oracle consensus required (admin only)
(define-public (set-oracle-consensus-required (count uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (> count u0) err-invalid-score)
    (var-set oracle-consensus-required count)
    (ok count)
  )
)
