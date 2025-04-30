;; VoteSure: Decentralized Insurance Smart Contract
;; The system leverages artificial intelligence and 
;;community governance to provide transparent, efficient, 
;; and fair insurance services without traditional intermediaries.

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_POLICY u2)
(define-constant ERR_INSUFFICIENT_FUNDS u3)
(define-constant ERR_POLICY_NOT_ACTIVE u4)
(define-constant ERR_CLAIM_ALREADY_EXISTS u5)
(define-constant ERR_CLAIM_NOT_FOUND u6)
(define-constant ERR_VOTING_CLOSED u7)

;; Data structures
(define-map policies
  { policy-id: uint }
  {
    owner: principal,
    premium: uint,
    coverage: uint,
    risk-score: uint,
    start-time: uint,
    end-time: uint,
    is-active: bool
  }
)

(define-map claims
  { claim-id: uint }
  {
    policy-id: uint,
    claimant: principal,
    amount: uint,
    description: (string-utf8 256),
    timestamp: uint,
    status: (string-utf8 20),
    ai-risk-assessment: uint,
    votes-for: uint,
    votes-against: uint,
    voting-end-time: uint
  }
)

(define-map user-votes
  { claim-id: uint, voter: principal }
  { vote: bool }
)

;; State variables
(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var governance-token (optional principal) none)
(define-data-var admin principal tx-sender)
(define-data-var ai-oracle principal tx-sender)
(define-data-var voting-period uint u144) ;; ~1 day in blocks

;; Read-only functions
(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-user-vote (claim-id uint) (voter principal))
  (map-get? user-votes { claim-id: claim-id, voter: voter })
)

;; Policy management functions
(define-public (create-policy (premium uint) (coverage uint) (duration uint))
  (let
    (
      (policy-id (var-get policy-counter))
      (start-time block-height)
      (end-time (+ block-height duration))
      (risk-score (assess-risk tx-sender premium coverage))
      (adjusted-premium (calculate-premium premium risk-score))
    )
    (asserts! (>= coverage (* adjusted-premium u2)) (err ERR_INVALID_POLICY))
    (try! (stx-transfer? adjusted-premium tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      {
        owner: tx-sender,
        premium: adjusted-premium,
        coverage: coverage,
        risk-score: risk-score,
        start-time: start-time,
        end-time: end-time,
        is-active: true
      }
    )
    
    (var-set policy-counter (+ policy-id u1))
    (ok policy-id)
  )
)

(define-read-only (assess-risk (user principal) (premium uint) (coverage uint))
  ;; Simulated AI risk assessment
  ;; In a real implementation, this would call an oracle or use more complex logic
  (let
    (
      (premium-factor (/ (* premium u100) coverage))
      ;; Use a simpler approach - just use block height as a pseudo-random factor
      ;; In a real implementation, you would want to use an oracle or more sophisticated randomness
      (random-factor (mod block-height u100))
    )
    (+ u50 (/ premium-factor u10) (/ random-factor u5))
  )
)

(define-read-only (calculate-premium (base-premium uint) (risk-score uint))
  (+ base-premium (/ (* base-premium risk-score) u100))
)

;; Define string constants for status values
(define-constant STATUS_PENDING u"pending")
(define-constant STATUS_APPROVED u"approved")
(define-constant STATUS_REJECTED u"rejected")

;; Claims processing functions
(define-public (submit-claim (policy-id uint) (amount uint) (description (string-utf8 256)))
  (let
    (
      (policy (unwrap! (get-policy policy-id) (err ERR_INVALID_POLICY)))
      (claim-id (var-get claim-counter))
    )
    (asserts! (is-eq (get owner policy) tx-sender) (err ERR_UNAUTHORIZED))
    (asserts! (get is-active policy) (err ERR_POLICY_NOT_ACTIVE))
    (asserts! (<= amount (get coverage policy)) (err ERR_INVALID_POLICY))
    
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: tx-sender,
        amount: amount,
        description: description,
        timestamp: block-height,
        status: STATUS_PENDING,
        ai-risk-assessment: u0, ;; Will be set by AI oracle
        votes-for: u0,
        votes-against: u0,
        voting-end-time: (+ block-height (var-get voting-period))
      }
    )
    
    (var-set claim-counter (+ claim-id u1))
    (ok claim-id)
  )
)

;; AI Oracle function to assess claim risk
(define-public (assess-claim-risk (claim-id uint) (risk-score uint))
  (let
    (
      (claim (unwrap! (get-claim claim-id) (err ERR_CLAIM_NOT_FOUND)))
    )
    (asserts! (is-eq tx-sender (var-get ai-oracle)) (err ERR_UNAUTHORIZED))
    
    (map-set claims
      { claim-id: claim-id }
      (merge claim { ai-risk-assessment: risk-score })
    )
    (ok true)
  )
)

;; Governance and voting functions
(define-public (vote-on-claim (claim-id uint) (vote bool))
  (let
    (
      (claim (unwrap! (get-claim claim-id) (err ERR_CLAIM_NOT_FOUND)))
      (current-votes-for (get votes-for claim))
      (current-votes-against (get votes-against claim))
    )
    (asserts! (< block-height (get voting-end-time claim)) (err ERR_VOTING_CLOSED))
    (asserts! (is-none (get-user-vote claim-id tx-sender)) (err ERR_UNAUTHORIZED))
    
    (map-set user-votes
      { claim-id: claim-id, voter: tx-sender }
      { vote: vote }
    )
    
    (if vote
      (map-set claims
        { claim-id: claim-id }
        (merge claim { votes-for: (+ current-votes-for u1) })
      )
      (map-set claims
        { claim-id: claim-id }
        (merge claim { votes-against: (+ current-votes-against u1) })
      )
    )
    (ok true)
  )
)

;; AI-enhanced claim resolution function
;; This function processes claims using both AI risk assessment and community voting
(define-public (resolve-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (get-claim claim-id) (err ERR_CLAIM_NOT_FOUND)))
      (policy (unwrap! (get-policy (get policy-id claim)) (err ERR_INVALID_POLICY)))
      (votes-for (get votes-for claim))
      (votes-against (get votes-against claim))
      (ai-risk-score (get ai-risk-assessment claim))
      (voting-weight u70)
      (ai-weight u30)
      (approval-threshold u60)
      (voting-score (if (> (+ votes-for votes-against) u0)
                       (/ (* votes-for u100) (+ votes-for votes-against))
                       u0))
      (inverse-risk-score (- u100 ai-risk-score))
      (combined-score (/ (+ (* voting-score voting-weight) 
                           (* inverse-risk-score ai-weight)) 
                        u100))
      (is-approved (>= combined-score approval-threshold))
    )
    
    ;; Ensure voting period has ended
    (asserts! (>= block-height (get voting-end-time claim)) (err ERR_VOTING_CLOSED))
    ;; Ensure claim is still pending
    (asserts! (is-eq (get status claim) STATUS_PENDING) (err ERR_UNAUTHORIZED))
    
    ;; Update claim status based on combined score
    (map-set claims
      { claim-id: claim-id }
      (merge claim { status: (if is-approved STATUS_APPROVED STATUS_REJECTED) })
    )
    
    ;; If approved, transfer funds to claimant
    (if is-approved
      (begin
        ;; Deactivate policy if full coverage is claimed
        (if (is-eq (get amount claim) (get coverage policy))
          (map-set policies
            { policy-id: (get policy-id claim) }
            (merge policy { is-active: false })
          )
          true
        )
        ;; Transfer claim amount to claimant
        (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))))
        (ok is-approved)
      )
      (ok is-approved)
    )
  )
)
