module Api
  module V1
    class PaymentsController < ApplicationController

      # POST /api/v1/payments
      def create
        idempotency_key = extract_idempotency_key
        return render_error("Idempotency-Key header is required", :unprocessable_entity) if idempotency_key.blank?

        # Idempotency check — return cached response for duplicate keys
        existing = Payment.find_by(idempotency_key: idempotency_key)
        if existing
          Rails.logger.info("[PaymentsController] Duplicate request — returning cached response for key: #{idempotency_key}, payment_id: #{existing.id}")
          return render json: payment_response(existing), status: :ok
        end

        payment = Payment.new(payment_params.merge(idempotency_key: idempotency_key))

        if payment.save
          ProcessPaymentJob.perform_later(payment.id)
          Rails.logger.info("[PaymentsController] Payment created and enqueued — payment_id: #{payment.id}, key: #{idempotency_key}")
          render json: payment_response(payment), status: :accepted
        else
          render_error(payment.errors.full_messages, :unprocessable_entity)
        end

      rescue ActiveRecord::RecordNotUnique
        # Race condition — two requests with same key hit simultaneously
        existing = Payment.find_by!(idempotency_key: idempotency_key)
        Rails.logger.warn("[PaymentsController] Race condition resolved — payment_id: #{existing.id}, key: #{idempotency_key}")
        render json: payment_response(existing), status: :ok
      end

      # GET /api/v1/payments/:id
      def show
        payment = Payment.find(params[:id])
        render json: payment_response(payment)
      rescue ActiveRecord::RecordNotFound
        render_error("Payment not found", :not_found)
      end

      # GET /api/v1/payments
      def index
        payments = Payment.recent.limit(50)
        payments = payments.where(status: params[:status]) if params[:status].present?
        payments = payments.where(payer_id: params[:payer_id]) if params[:payer_id].present?
        render json: { payments: payments.map { |p| payment_response(p) }, count: payments.size }
      end

      # DELETE /api/v1/payments/:id/cancel
      def cancel
        payment = Payment.find(params[:id])
        payment.mark_cancelled!
        Rails.logger.info("[PaymentsController] Payment cancelled — payment_id: #{payment.id}")
        render json: payment_response(payment)
      rescue ActiveRecord::RecordNotFound
        render_error("Payment not found", :not_found)
      rescue Payment::NotCancellable => e
        render_error(e.message, :conflict)
      end

      private

      def payment_params
        params.require(:payment).permit(:amount, :currency, :payer_id, :payee_id, :description, metadata: {})
      end

      def extract_idempotency_key
        request.headers["Idempotency-Key"] || params.dig(:payment, :idempotency_key)
      end

      def payment_response(payment)
        {
          id:                payment.id,
          idempotency_key:   payment.idempotency_key,
          status:            payment.status,
          amount:            payment.amount.to_s,
          currency:          payment.currency,
          payer_id:          payment.payer_id,
          payee_id:          payment.payee_id,
          description:       payment.description,
          attempts:          payment.attempts,
          error_message:     payment.error_message,
          gateway_reference: payment.gateway_reference,
          processed_at:      payment.processed_at&.iso8601,
          cancelled_at:      payment.cancelled_at&.iso8601,
          created_at:        payment.created_at.iso8601,
          updated_at:        payment.updated_at.iso8601
        }
      end

      def render_error(message, status)
        render json: { error: Array(message).join(", ") }, status: status
      end
    end
  end
end