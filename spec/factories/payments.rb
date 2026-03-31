FactoryBot.define do
  factory :payment do
    idempotency_key { SecureRandom.uuid }
    amount          { 250.00 }
    currency        { "USD" }
    payer_id        { "payer_#{SecureRandom.hex(4)}" }
    payee_id        { "payee_#{SecureRandom.hex(4)}" }
    description     { "Test payment" }
    status          { "pending" }
    attempts        { 0 }
    metadata        { {} }

    trait :pending do
      status   { "pending" }
      attempts { 0 }
    end

    trait :processing do
      status   { "processing" }
      attempts { 1 }
    end

    trait :completed do
      status             { "completed" }
      attempts           { 1 }
      gateway_reference  { "GW-#{SecureRandom.hex(8).upcase}" }
      processed_at       { Time.current }
    end

    trait :failed do
      status        { "failed" }
      attempts      { 5 }
      error_message { "Insufficient funds" }
    end

    trait :cancelled do
      status       { "cancelled" }
      cancelled_at { Time.current }
    end
  end
end