;; Spectra Runtime - Supply Chain Intelligence Platform
;; Version: 1.0.0
;; Clarity Version: 2
;; Epoch: 2.1

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-score (err u104))
(define-constant err-invalid-status (err u105))

;; Data Variables
(define-data-var platform-enabled bool true)
(define-data-var min-trust-score uint u50)
(define-data-var validator-count uint u0)

;; Data Maps

;; Vendor Registry
(define-map vendors
    { vendor-id: uint }
    {
        name: (string-ascii 100),
        trust-score: uint,
        total-transactions: uint,
        compliant: bool,
        registered-at: uint,
        validator: principal
    }
)

;; Product Provenance - Cryptographic DNA
(define-map products
    { product-id: (string-ascii 64) }
    {
        vendor-id: uint,
        name: (string-ascii 100),
        batch-number: (string-ascii 50),
        timestamp: uint,
        origin: (string-ascii 100),
        certifications: (list 10 (string-ascii 50)),
        verified: bool
    }
)

;; Compliance Records
(define-map compliance-records
    { vendor-id: uint, record-id: uint }
    {
        framework: (string-ascii 20),
        status: (string-ascii 20),
        last-audit: uint,
        expiry: uint,
        auditor: principal
    }
)

;; Risk Assessments
(define-map risk-assessments
    { vendor-id: uint }
    {
        operational-risk: uint,
        financial-risk: uint,
        compliance-risk: uint,
        overall-score: uint,
        last-updated: uint
    }
)

;; Validators (Proof of Compliance)
(define-map validators
    { validator: principal }
    {
        domain-expertise: (string-ascii 50),
        accuracy-score: uint,
        validations-performed: uint,
        active: bool
    }
)

;; Transaction History
(define-map transactions
    { tx-id: uint }
    {
        vendor-id: uint,
        product-id: (string-ascii 64),
        quantity: uint,
        timestamp: uint,
        status: (string-ascii 20)
    }
)

;; Dispute Cases
(define-map disputes
    { dispute-id: uint }
    {
        vendor-id: uint,
        product-id: (string-ascii 64),
        filed-by: principal,
        status: (string-ascii 20),
        filed-at: uint,
        resolved-at: (optional uint)
    }
)

;; Read-only Functions

(define-read-only (get-vendor (vendor-id uint))
    (map-get? vendors { vendor-id: vendor-id })
)

(define-read-only (get-product (product-id (string-ascii 64)))
    (map-get? products { product-id: product-id })
)

(define-read-only (get-compliance-record (vendor-id uint) (record-id uint))
    (map-get? compliance-records { vendor-id: vendor-id, record-id: record-id })
)

(define-read-only (get-risk-assessment (vendor-id uint))
    (map-get? risk-assessments { vendor-id: vendor-id })
)

(define-read-only (get-validator (validator principal))
    (map-get? validators { validator: validator })
)

(define-read-only (is-vendor-compliant (vendor-id uint))
    (match (map-get? vendors { vendor-id: vendor-id })
        vendor (ok (get compliant vendor))
        (err err-not-found)
    )
)

(define-read-only (get-vendor-trust-score (vendor-id uint))
    (match (map-get? vendors { vendor-id: vendor-id })
        vendor (ok (get trust-score vendor))
        (err err-not-found)
    )
)

(define-read-only (get-platform-status)
    (ok {
        enabled: (var-get platform-enabled),
        min-trust-score: (var-get min-trust-score),
        validator-count: (var-get validator-count)
    })
)

;; Public Functions

;; Register a new vendor
(define-public (register-vendor 
    (vendor-id uint)
    (name (string-ascii 100))
    (initial-trust-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? vendors { vendor-id: vendor-id })) err-already-exists)
        (asserts! (<= initial-trust-score u100) err-invalid-score)
        (ok (map-set vendors
            { vendor-id: vendor-id }
            {
                name: name,
                trust-score: initial-trust-score,
                total-transactions: u0,
                compliant: true,
                registered-at: block-height,
                validator: tx-sender
            }
        ))
    )
)

;; Update vendor trust score
(define-public (update-trust-score 
    (vendor-id uint)
    (new-score uint))
    (let
        (
            (vendor (unwrap! (map-get? vendors { vendor-id: vendor-id }) err-not-found))
        )
        (asserts! (or (is-eq tx-sender contract-owner) 
                     (is-eq tx-sender (get validator vendor))) err-unauthorized)
        (asserts! (<= new-score u100) err-invalid-score)
        (ok (map-set vendors
            { vendor-id: vendor-id }
            (merge vendor { trust-score: new-score })
        ))
    )
)

;; Register a product with cryptographic DNA
(define-public (register-product
    (product-id (string-ascii 64))
    (vendor-id uint)
    (name (string-ascii 100))
    (batch-number (string-ascii 50))
    (origin (string-ascii 100))
    (certifications (list 10 (string-ascii 50))))
    (begin
        (asserts! (is-some (map-get? vendors { vendor-id: vendor-id })) err-not-found)
        (asserts! (is-none (map-get? products { product-id: product-id })) err-already-exists)
        (ok (map-set products
            { product-id: product-id }
            {
                vendor-id: vendor-id,
                name: name,
                batch-number: batch-number,
                timestamp: block-height,
                origin: origin,
                certifications: certifications,
                verified: false
            }
        ))
    )
)

;; Verify product
(define-public (verify-product (product-id (string-ascii 64)))
    (let
        (
            (product (unwrap! (map-get? products { product-id: product-id }) err-not-found))
            (validator-info (unwrap! (map-get? validators { validator: tx-sender }) err-unauthorized))
        )
        (asserts! (get active validator-info) err-unauthorized)
        (ok (map-set products
            { product-id: product-id }
            (merge product { verified: true })
        ))
    )
)

;; Add compliance record
(define-public (add-compliance-record
    (vendor-id uint)
    (record-id uint)
    (framework (string-ascii 20))
    (status (string-ascii 20))
    (expiry uint))
    (begin
        (asserts! (is-some (map-get? vendors { vendor-id: vendor-id })) err-not-found)
        (ok (map-set compliance-records
            { vendor-id: vendor-id, record-id: record-id }
            {
                framework: framework,
                status: status,
                last-audit: block-height,
                expiry: expiry,
                auditor: tx-sender
            }
        ))
    )
)

;; Update risk assessment
(define-public (update-risk-assessment
    (vendor-id uint)
    (operational-risk uint)
    (financial-risk uint)
    (compliance-risk uint))
    (let
        (
            (overall-score (/ (+ operational-risk (+ financial-risk compliance-risk)) u3))
        )
        (asserts! (is-some (map-get? vendors { vendor-id: vendor-id })) err-not-found)
        (asserts! (and (<= operational-risk u100) 
                      (and (<= financial-risk u100) 
                           (<= compliance-risk u100))) err-invalid-score)
        (ok (map-set risk-assessments
            { vendor-id: vendor-id }
            {
                operational-risk: operational-risk,
                financial-risk: financial-risk,
                compliance-risk: compliance-risk,
                overall-score: overall-score,
                last-updated: block-height
            }
        ))
    )
)

;; Register validator
(define-public (register-validator
    (validator principal)
    (domain-expertise (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? validators { validator: validator })) err-already-exists)
        (var-set validator-count (+ (var-get validator-count) u1))
        (ok (map-set validators
            { validator: validator }
            {
                domain-expertise: domain-expertise,
                accuracy-score: u100,
                validations-performed: u0,
                active: true
            }
        ))
    )
)

;; Record transaction
(define-public (record-transaction
    (tx-id uint)
    (vendor-id uint)
    (product-id (string-ascii 64))
    (quantity uint))
    (let
        (
            (vendor (unwrap! (map-get? vendors { vendor-id: vendor-id }) err-not-found))
        )
        (asserts! (is-some (map-get? products { product-id: product-id })) err-not-found)
        (map-set vendors
            { vendor-id: vendor-id }
            (merge vendor { total-transactions: (+ (get total-transactions vendor) u1) })
        )
        (ok (map-set transactions
            { tx-id: tx-id }
            {
                vendor-id: vendor-id,
                product-id: product-id,
                quantity: quantity,
                timestamp: block-height,
                status: "completed"
            }
        ))
    )
)

;; File dispute
(define-public (file-dispute
    (dispute-id uint)
    (vendor-id uint)
    (product-id (string-ascii 64)))
    (begin
        (asserts! (is-some (map-get? vendors { vendor-id: vendor-id })) err-not-found)
        (asserts! (is-some (map-get? products { product-id: product-id })) err-not-found)
        (ok (map-set disputes
            { dispute-id: dispute-id }
            {
                vendor-id: vendor-id,
                product-id: product-id,
                filed-by: tx-sender,
                status: "pending",
                filed-at: block-height,
                resolved-at: none
            }
        ))
    )
)

;; Resolve dispute
(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 20)))
    (let
        (
            (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute { 
                status: resolution,
                resolved-at: (some block-height)
            })
        ))
    )
)

;; Toggle vendor compliance status
(define-public (set-vendor-compliance (vendor-id uint) (compliant bool))
    (let
        (
            (vendor (unwrap! (map-get? vendors { vendor-id: vendor-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set vendors
            { vendor-id: vendor-id }
            (merge vendor { compliant: compliant })
        ))
    )
)

;; Admin Functions

(define-public (set-platform-enabled (enabled bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (var-set platform-enabled enabled))
    )
)

(define-public (set-min-trust-score (score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= score u100) err-invalid-score)
        (ok (var-set min-trust-score score))
    )
)
