require "rails_helper"

RSpec.describe "Api::V1::Payments", type: :request do
  let(:valid_params) do
    {
      payment: {
        amount:      "250.00",
        currency:    "USD",
        payer_id:    "payer_abc123",
        payee_id:    "payee_xyz789",
        description: "Test payment"
      }
    }
  end
  let(:idempotency_key) { SecureRandom.uuid }
  let(:headers) { { "Idempotency-Key" => idempotency_key, "Content-Type" => "application/json" } }

  describe "POST /api/v1/payments" do
    context "with valid params" do
      it "creates a payment and enqueues a job" do
        expect {
          post "/api/v1/payments", params: valid_params.to_json, headers: headers
        }.to change(Payment, :count).by(1)
           .and have_enqueued_job(ProcessPaymentJob)

        expect(response).to have_http_status(:accepted)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("pending")
        expect(json["idempotency_key"]).to eq(idempotency_key)
      end
    end

    context "duplicate idempotency key (second request)" do
      let!(:existing) { create(:payment, idempotency_key: idempotency_key) }

      it "returns the existing payment without creating a new one or re-enqueuing" do
        expect {
          post "/api/v1/payments", params: valid_params.to_json, headers: headers
        }.not_to change(Payment, :count)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["id"]).to eq(existing.id)
      end
    end

    context "missing idempotency key" do
      it "returns 422" do
        post "/api/v1/payments", params: valid_params.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "invalid params" do
      it "returns validation errors for negative amount" do
        params = valid_params.deep_merge(payment: { amount: "-10" })
        post "/api/v1/payments", params: params.to_json, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /api/v1/payments/:id" do
    let!(:payment) { create(:payment) }

    it "returns payment details" do
      get "/api/v1/payments/#{payment.id}"
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(payment.id)
    end

    it "returns 404 for unknown ID" do
      get "/api/v1/payments/#{SecureRandom.uuid}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/payments/:id/cancel" do
    context "pending payment" do
      let!(:payment) { create(:payment, :pending) }

      it "cancels the payment" do
        delete "/api/v1/payments/#{payment.id}/cancel"
        expect(response).to have_http_status(:ok)
        expect(payment.reload.status).to eq("cancelled")
      end
    end

    context "already processing" do
      let!(:payment) { create(:payment, :processing) }

      it "returns 409 conflict" do
        delete "/api/v1/payments/#{payment.id}/cancel"
        expect(response).to have_http_status(:conflict)
      end
    end

    context "completed payment" do
      let!(:payment) { create(:payment, :completed) }

      it "returns 409 conflict" do
        delete "/api/v1/payments/#{payment.id}/cancel"
        expect(response).to have_http_status(:conflict)
      end
    end
  end
end
