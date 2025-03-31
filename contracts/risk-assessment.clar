;; BTC Shield - Risk Assessment Smart Contract
;; Enhanced with oracle system for risk assessment

;; Data Maps
(define-map risk-oracles
  principal
  {
    oracle-name: (string-ascii 50),
    reliability-score: uint,
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

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u401))
(define-constant err-not-found (err u404))
(define-constant err-invalid-score (err u405))
(define-constant err-invalid-confidence (err u406))

;; Variables
(define-data-var min-confidence-threshold uint u60)

;; Functions

;; Register as a risk oracle
(define-public (register-oracle (oracle-name (string-ascii 50)))
  (begin
    ;; In a production system, we would verify the oracle's identity and credentials
    (map-set risk-oracles tx-sender {
      oracle-name: oracle-name,
      reliability-score: u500, ;; Starting at 50% reliability
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
  )
    ;; If we have an assessment, use it to calculate risk factor, otherwise use default
    (if (is-some assessment)
      (let (
        (risk-data (unwrap-panic assessment))
        (risk-score (get risk-score risk-data))
        (confidence (get confidence risk-data))
        ;; Adjust risk by confidence
        (adjusted-risk (* risk-score (/ confidence u100)))
      )
        ;; Convert adjusted risk to basis points (50-500)
        (+ u50 (/ (* adjusted-risk u450) u1000))
      )
      ;; Default risk factor of 200 (2%)
      u200)
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

;; Get oracle information
(define-read-only (get-oracle-info (oracle principal))
  (map-get? risk-oracles oracle)
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
