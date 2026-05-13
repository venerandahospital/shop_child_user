# Subscription Quickstart (Manual First)

This gives you a fast path for paid monthly subscriptions:

- Client pays your mobile money number
- You confirm payment
- You generate activation code
- Client enters code in app

## Phase A (Today): Local generator script

The project now includes:

- `tools/subscription_code_tool.dart`

### 1) Generate a code

```bash
dart run tools/subscription_code_tool.dart generate --license SHOP-001 --business BUS-001 --owner "Client Name" --days 30 --max-devices 2 --secret "CHANGE_ME_SECRET"
```

This prints a code like:

`LABSUB1.<payload>.<signature>`

Business code in the command (`--business`) must match what the client enters in app.

### 2) Verify a code

```bash
dart run tools/subscription_code_tool.dart verify --code "LABSUB1...." --secret "CHANGE_ME_SECRET"
```

### Important

- Keep the `secret` private (owner-only).
- Do NOT embed this secret in public clients.
- For production, move generation/signing to backend (Phase B).

---

## Phase B: Backend API contracts (recommended)

Use these endpoints in your backend (Quarkus):

### 1) Generate code (owner/admin only)

`POST /admin/subscriptions/codes`

Request:

```json
{
  "licenseId": "SHOP-001",
  "businessCode": "BUS-001",
  "ownerName": "Client Name",
  "durationDays": 30,
  "maxDevices": 2,
  "paymentReference": "MM-TRX-12345"
}
```

Response:

```json
{
  "activationCode": "LABSUB1....",
  "issuedAt": "2026-04-26T15:00:00Z",
  "expiresAt": "2026-05-26T15:00:00Z",
  "status": "ACTIVE"
}
```

### 2) Activate from app

`POST /subscriptions/activate`

Request:

```json
{
  "activationCode": "LABSUB1....",
  "businessCode": "BUS-001",
  "deviceId": "DEVICE-UNIQUE-ID",
  "appVersion": "1.0.0"
}
```

Response:

```json
{
  "ok": true,
  "licenseId": "SHOP-001",
  "activeFrom": "2026-04-26T15:00:00Z",
  "activeUntil": "2026-05-26T15:00:00Z",
  "daysRemaining": 30
}
```

### 3) Status check (optional but useful)

`GET /subscriptions/status?licenseId=SHOP-001&deviceId=DEVICE-UNIQUE-ID`

Response:

```json
{
  "status": "ACTIVE",
  "activeUntil": "2026-05-26T15:00:00Z",
  "daysRemaining": 18
}
```

---

## Phase C: Owner admin page

Small internal web page:

- Search customer/shop
- Enter payment reference
- Click **Generate code**
- Copy/send code (SMS/WhatsApp)
- See generated code history

---

## App policy to implement

- Day 1-24: normal
- Day 25-30: reminders, app still usable
- Day 31+: block app routes and force activation page

## Important: max 2 phones rule

The activation code now carries `maxDevices=2`, but strict cross-phone enforcement requires a shared online registry/backend.

- Offline-only app cannot reliably count devices across different phones.
- Enforce this in backend using: `businessCode + activationCode + deviceId`.

