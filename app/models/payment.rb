class Payment < ApplicationRecord
  # ── Enums ──────────────────────────────────────────────────────────────────
  enum status: {
    pending:    "pending",
    processing: "processing",
    completed:  "completed",
    failed:     "failed",
    cancelled:  "cancelled"
  }, _prefix: :status

  # ── Validations ────────────────────────────────────────────────────────────
  validates :idempotency_key, presence: true, uniqueness: true,
                              format: { with: /\A[\w\-]{8,64}\z/, message: "must be 8-64 alphanumeric/dash/underscore chars" }
  validates :amount,          presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :currency,        presence: true, inclusion: { in: %w[USD EUR GBP INR AUD] }
  validates :payer_id,        presence: true
  validates :payee_id,        presence: true
  validates :status,          presence: true

  # ── Callbacks ──────────────────────────────────────────────────────────────
  before_validation :set_idempotency_key, on: :create

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :recent,      -> { order(created_at: :desc) }
  scope :retryable,   -> { where(status: [:pending, :failed]).where("attempts < ?", MAX_ATTEMPTS) }
  scope :stale,       -> { where(status: :processing).where("updated_at < ?", 10.minutes.ago) }

  MAX_ATTEMPTS = 5

  # ── State transitions ─────────────────────────────────────────────────────

  # Atomically transition to processing — prevents race conditions
  # Returns false if already being processed by another worker
#   def mark_processing!
#     with_advisory_lock("payment_processing_#{id}") do
#       return false unless status_pending? || status_failed?

#       update!(status: :processing, attempts: attempts + 1)
#       true
#     end
#   end

    def mark_processing!
    rows_updated = Payment.where(id: id, status: ["pending", "failed"])
                            .where("attempts < ?", MAX_ATTEMPTS)  # ← add this line
                            .update_all(status: "processing", attempts: attempts + 1, updated_at: Time.current)

    if rows_updated == 1
        reload
        true
    else
        false
    end
    end

  def mark_completed!(gateway_reference:)
    update!(
      status:            :completed,
      gateway_reference: gateway_reference,
      processed_at:      Time.current,
      error_message:     nil
    )
  end

  def mark_failed!(error_message:)
    update!(
      status:        attempts >= MAX_ATTEMPTS ? :failed : :pending,
      error_message: error_message
    )
  end

  def mark_cancelled!
    raise Payment::NotCancellable, "Cannot cancel a #{status} payment" unless cancellable?

    update!(status: :cancelled, cancelled_at: Time.current)
  end

  def cancellable?
    status_pending?
  end

  def retryable?
    (status_pending? || status_failed?) && attempts < MAX_ATTEMPTS
  end

  def terminal?
    status_completed? || status_cancelled?
  end

  # ── Errors ────────────────────────────────────────────────────────────────
  class NotCancellable < StandardError; end
  class DuplicateRequest < StandardError
    attr_reader :existing_payment
    def initialize(existing_payment)
      @existing_payment = existing_payment
      super("Duplicate idempotency key: #{existing_payment.idempotency_key}")
    end
  end

  private

  def set_idempotency_key
    self.idempotency_key ||= SecureRandom.uuid
  end
end
