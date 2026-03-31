class ProcessPaymentJob < ApplicationJob
  queue_as :payments

  # Define FIRST — retry_on references this constant at class load time
  class PaymentProcessingError < StandardError; end

  retry_on PaymentProcessingError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(payment_id)
    payment = Payment.find_by(id: payment_id)

    # Guard: payment not found
    unless payment
      Rails.logger.error("[ProcessPaymentJob] Payment not found — payment_id: #{payment_id}")
      return
    end

    # Guard: already in a terminal state — do not reprocess
    if payment.terminal?
      Rails.logger.info("[ProcessPaymentJob] Skipping — payment is #{payment.status} (payment_id: #{payment.id})")
      return
    end

    # Guard: advisory lock — prevents two workers processing the same payment
    unless payment.mark_processing!
      Rails.logger.warn("[ProcessPaymentJob] Could not acquire lock — skipping (payment_id: #{payment.id})")
      return
    end

    Rails.logger.info("[ProcessPaymentJob] Processing started — payment_id: #{payment.id}, attempt: #{payment.attempts}")

    # Call downstream gateway
    result = PaymentProcessorService.new(payment).call

    if result.success?
      payment.mark_completed!(gateway_reference: result.gateway_reference)
      Rails.logger.info("[ProcessPaymentJob] Completed — payment_id: #{payment.id}, ref: #{result.gateway_reference}")
    else
      payment.mark_failed!(error_message: result.error_message)
      Rails.logger.warn("[ProcessPaymentJob] Failed — payment_id: #{payment.id}, error: #{result.error_message}, attempts: #{payment.attempts}")

      # Raise to trigger Active Job retry if attempts remain
      raise PaymentProcessingError, result.error_message if payment.retryable?
    end
  end

end