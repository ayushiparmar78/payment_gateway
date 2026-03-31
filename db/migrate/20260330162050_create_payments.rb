class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.string  :idempotency_key, null: false
      t.string  :status,          null: false, default: "pending"
      t.decimal :amount,          null: false, precision: 12, scale: 2
      t.string  :currency,        null: false, default: "USD"
      t.string  :payer_id,        null: false
      t.string  :payee_id,        null: false
      t.string  :description
      t.integer :attempts,        null: false, default: 0
      t.string  :error_message    # last failure reason
      t.string   :gateway_reference   # filled on success by downstream gateway
      t.datetime :processed_at        # when payment completed successfully
      t.datetime :cancelled_at        # when payment was cancelled
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payments, :idempotency_key,
              unique: true,
              name: "idx_payments_idempotency_key_unique"

    add_index :payments, :status,
              name: "idx_payments_status"

    add_index :payments, :payer_id,
              name: "idx_payments_payer_id"

    add_index :payments, [:payer_id, :status],
              name: "idx_payments_payer_id_status"

    add_index :payments, :created_at,
              name: "idx_payments_created_at"
  end
end
