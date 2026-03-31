# PaymentGateway — Rails Assignment

A production-grade payment processing service built with Ruby on Rails 7, demonstrating idempotency, background job processing, retry logic, concurrency safety, and downstream failure handling.

## Setup

### Prerequisites
- Ruby 3.2.2
- PostgreSQL
- Redis

```bash
git clone <repo>
cd payment_gateway
bundle install

# Configure DB
cp config/database.yml.example config/database.yml
# edit credentials if needed

rails db:create db:migrate

# Start Redis (in a separate terminal)
redis-server

# Start Sidekiq (in a separate terminal)
bundle exec sidekiq -q payments -c 5

# Start Rails
rails s
```

---

## API Reference

### Create Payment
```
POST /api/v1/payments
Header: Idempotency-Key: <uuid>
```
```json
{
  "payment": {
    "amount": "250.00",
    "currency": "USD",
    "payer_id": "payer_abc123",
    "payee_id": "payee_xyz789",
    "description": "Invoice #1042"
  }
}
```
**Response:** `202 Accepted` — payment created and enqueued.  
**Duplicate key:** `200 OK` — returns the existing payment (no new record, no re-enqueue).

### Get Payment
```
GET /api/v1/payments/:id
```
Returns current status, attempts, gateway reference, error message.

### List Payments
```
GET /api/v1/payments?status=pending&payer_id=payer_abc123
```

### Cancel Payment
```
DELETE /api/v1/payments/:id/cancel
```
- `200` if cancelled successfully  
- `409 Conflict` if payment is already processing, completed, or failed

---

## How Each Assignment Scenario Is Handled

### 1. Idempotency / Duplicate Request Prevention

Two layers of protection:

**Layer 1 — Application check** (`PaymentsController#create`):
```ruby
existing = Payment.find_by(idempotency_key: idempotency_key)
return render json: payment_response(existing), status: :ok if existing
```

**Layer 2 — DB unique constraint** (migration):
```ruby
add_index :payments, :idempotency_key, unique: true
```

If two requests race and both pass the application check simultaneously, the DB constraint catches the second one. The controller rescues `ActiveRecord::RecordNotUnique` and returns the winner's record — no error, no duplicate.

### 2. Retry Logic Without Duplication

Sidekiq retries the job up to 5 times with exponential backoff:
```ruby
sidekiq_options retry: 5
sidekiq_retry_in { |count| (count ** 2) * 10 + rand(10) }
# Retries at: ~10s, ~40s, ~90s, ~160s, ~250s
```

The job checks `payment.terminal?` before every execution — if the payment was already completed or cancelled by a previous attempt, it exits immediately. This prevents double-processing on retries.

### 3. Downstream Failure Handling

`PaymentProcessorService` simulates:
- 15% random gateway rejections (card declined, insufficient funds, etc.)
- 5% timeout failures

Failures are caught, logged, and returned as a `Result` struct. The job then:
- Updates `status` and `error_message`
- Re-raises `PaymentProcessingError` to trigger Sidekiq's retry if attempts remain
- After `MAX_ATTEMPTS` (5), marks the payment as permanently `failed`

### 4. Concurrency / Race Conditions

`Payment#mark_processing!` uses a PostgreSQL advisory lock:
```ruby
def mark_processing!
  with_advisory_lock("payment_processing_#{id}") do
    return false unless status_pending? || status_failed?
    update!(status: :processing, attempts: attempts + 1)
    true
  end
end
```

If two Sidekiq workers receive the same job simultaneously (e.g. a retried job + original), only one acquires the lock. The other gets `false` and exits without processing. This prevents double charges.

### 5. Cancellation Handling

Cancellation is only allowed in `pending` state. The model enforces this:
```ruby
def mark_cancelled!
  raise Payment::NotCancellable unless cancellable?
  update!(status: :cancelled, cancelled_at: Time.current)
end

def cancellable?
  status_pending?
end
```

The controller maps `NotCancellable` → `409 Conflict` with a clear error message.

---

## Database Schema

```
payments
├── id              (uuid, PK)
├── idempotency_key (string, UNIQUE INDEX)
├── status          (string: pending|processing|completed|failed|cancelled)
├── amount          (decimal 12,2)
├── currency        (string)
├── payer_id        (string, INDEX)
├── payee_id        (string)
├── description     (string)
├── attempts        (integer, default: 0)
├── error_message   (string)
├── gateway_reference (string)
├── metadata        (jsonb)
├── processed_at    (datetime)
├── cancelled_at    (datetime)
└── created_at / updated_at
```

**Indexes:**
- `idempotency_key` — unique, used for duplicate detection
- `status` — for filtering and stale job detection
- `payer_id` — for per-user payment queries
- `[payer_id, status]` — composite for filtered queries
- `created_at` — for range queries and pagination

---

## Running Tests

```bash
bundle exec rspec                          # all specs
bundle exec rspec spec/requests            # API endpoint tests
bundle exec rspec spec/jobs                # job retry/idempotency/concurrency tests
bundle exec rspec spec/services            # gateway failure simulation tests
```

---

## Postman Collection

Import `postman/payment_gateway.postman_collection.json`.

The collection covers:
1. Happy path — create payment, verify 202
2. Duplicate key — verify 200 with same payment ID
3. Get payment status
4. List with filters
5. Cancel payment
6. Missing `Idempotency-Key` header — expect 422
7. Invalid amount — expect 422

---

## Performance Notes

- **Indexes** on `idempotency_key`, `status`, and `payer_id` keep lookups O(log n)
- **Advisory locks** are row-level and non-blocking for different payment IDs — no global bottleneck
- **Sidekiq concurrency** is set to 5 workers on the `payments` queue — tune via `sidekiq.yml`
- Load test with JMeter: send 100 concurrent `POST /payments` with the same `Idempotency-Key` — only one payment record should be created

---

## Sidekiq Web UI

Visit `http://localhost:3000/sidekiq` to monitor queues, retries, and dead jobs.
