class PaymentProcessorService
  # Simulated downstream gateway failure rates (realistic for load testing)
  FAILURE_RATE       = 0.15  # 15% random failures
  TIMEOUT_RATE       = 0.05  # 5% timeouts
  SIMULATED_LATENCY  = 0.3   # seconds

  Result = Struct.new(:success, :gateway_reference, :error_message, keyword_init: true) do
    def success? = success
    def failure? = !success
  end

  def initialize(payment)
    @payment = payment
  end

  def call
    Rails.logger.info("[PaymentProcessor] Starting processing", payment_context)

    simulate_network_latency
    check_for_timeout
    check_for_failure

    # ── Happy path ──────────────────────────────────────────────────────────
    gateway_ref = generate_gateway_reference
    Rails.logger.info("[PaymentProcessor] Completed successfully", payment_context.merge(gateway_reference: gateway_ref))

    Result.new(success: true, gateway_reference: gateway_ref)

  rescue GatewayTimeoutError => e
    Rails.logger.warn("[PaymentProcessor] Gateway timeout", payment_context.merge(error: e.message))
    Result.new(success: false, error_message: "Gateway timeout: #{e.message}")

  rescue GatewayError => e
    Rails.logger.warn("[PaymentProcessor] Gateway error", payment_context.merge(error: e.message))
    Result.new(success: false, error_message: "Gateway error: #{e.message}")
  end

  private

  def simulate_network_latency
    sleep(SIMULATED_LATENCY + rand * 0.2)
  end

  def check_for_timeout
    raise GatewayTimeoutError, "Connection timed out after 30s" if rand < TIMEOUT_RATE
  end

  def check_for_failure
    if rand < FAILURE_RATE
      reasons = [
        "Insufficient funds",
        "Card declined by issuer",
        "Invalid account number",
        "Transaction limit exceeded"
      ]
      raise GatewayError, reasons.sample
    end
  end

  def generate_gateway_reference
    "GW-#{SecureRandom.hex(8).upcase}"
  end

  def payment_context
    {
      payment_id:       @payment.id,
      idempotency_key:  @payment.idempotency_key,
      amount:           @payment.amount,
      currency:         @payment.currency,
      attempt:          @payment.attempts
    }
  end

  # ── Custom errors ─────────────────────────────────────────────────────────
  class GatewayError        < StandardError; end
  class GatewayTimeoutError < StandardError; end
end
