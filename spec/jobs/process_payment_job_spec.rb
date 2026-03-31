require "rails_helper"

RSpec.describe ProcessPaymentJob, type: :job do
  describe "#perform" do
    let(:payment) { create(:payment, :pending) }
    let(:success_result) do
      PaymentProcessorService::Result.new(
        success: true,
        gateway_reference: "GW-ABCDEF12"
      )
    end
    let(:failure_result) do
      PaymentProcessorService::Result.new(
        success: false,
        error_message: "Insufficient funds"
      )
    end

    context "successful processing" do
      before do
        allow_any_instance_of(PaymentProcessorService).to receive(:call).and_return(success_result)
      end

      it "marks payment as completed" do
        described_class.new.perform(payment.id)
        payment.reload
        expect(payment.status).to eq("completed")
        expect(payment.gateway_reference).to eq("GW-ABCDEF12")
        expect(payment.processed_at).to be_present
      end
    end

    context "gateway failure (retriable)" do
      before do
        allow_any_instance_of(PaymentProcessorService).to receive(:call).and_return(failure_result)
      end

      it "marks payment as pending and raises for retry" do
        expect {
          described_class.new.perform(payment.id)
        }.to raise_error(ProcessPaymentJob::PaymentProcessingError)

        payment.reload
        expect(payment.status).to eq("pending")
        expect(payment.attempts).to eq(1)
        expect(payment.error_message).to eq("Insufficient funds")
      end
    end

    context "payment already completed (idempotency guard)" do
      let(:payment) { create(:payment, :completed) }

      it "skips processing without calling the gateway" do
        expect(PaymentProcessorService).not_to receive(:new)
        described_class.new.perform(payment.id)
      end
    end

    context "payment was cancelled" do
      let(:payment) { create(:payment, :cancelled) }

      it "skips processing" do
        expect(PaymentProcessorService).not_to receive(:new)
        described_class.new.perform(payment.id)
      end
    end

    context "payment not found" do
      it "logs and returns gracefully without raising" do
        expect {
          described_class.new.perform(SecureRandom.uuid)
        }.not_to raise_error
      end
    end

    context "concurrent workers — race condition protection" do
      it "only processes once when two workers receive the same job" do
        call_count = 0
        allow_any_instance_of(PaymentProcessorService).to receive(:call) do
          call_count += 1
          success_result
        end

        # Simulate two job instances running in sequence
        # (advisory lock ensures the second is skipped)
        job1 = described_class.new
        job2 = described_class.new

        job1.perform(payment.id)

        # After job1 completes, payment is terminal — job2 skips
        job2.perform(payment.id)

        expect(call_count).to eq(1)
        expect(payment.reload.status).to eq("completed")
      end
    end

    context "max retries exhausted" do
    let(:payment) { create(:payment, :failed, attempts: Payment::MAX_ATTEMPTS) }

    it "does not retry further" do
        expect(PaymentProcessorService).not_to receive(:new)  # ← should never reach the service
        described_class.new.perform(payment.id)
        expect(payment.reload.attempts).to eq(Payment::MAX_ATTEMPTS)
    end
    end
  end
end
