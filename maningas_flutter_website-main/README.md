# Gonzales Vision Clinic Patient Portal

This repository contains the Flutter Web patient-portal frontend. It does not
contain the online backend/server implementation. API URLs and JSON contracts
in this app are client integrations only; backend routes, database access,
password hashing, OTP lifecycle, authorization, CORS, and deployment settings
must be edited and verified in the existing backend repository.

## Run locally

The app starts at the API-backed sign-in page. Configure the API host with
`PATIENT_API_BASE_URL` when it differs from the production default:

```powershell
flutter run -d chrome -t lib\main.dart `
  --dart-define=PATIENT_API_BASE_URL=https://api.gonzalesvisionclinic.com
```

For local development, HTTP is allowed only for `localhost`, `127.0.0.1`, or
`::1`. All other API hosts must use HTTPS. There is no demo-auth switch or
sample account data.

## Deploy to Vercel through GitHub

The repository includes a GitHub Actions workflow that builds this Flutter Web
app and deploys the generated `build/web` files to Vercel whenever a commit is
pushed to `main`.

1. Create or import a Vercel project for this app. If prompted for a project
   root, select `maningas_flutter_website-main`.
2. In Vercel, find the project and team IDs in its settings, and create a Vercel
   access token.
3. In the GitHub repository, open **Settings > Secrets and variables >
   Actions** and add these repository secrets:
   - `VERCEL_TOKEN` — the Vercel access token.
   - `VERCEL_ORG_ID` — the Vercel team/user ID.
   - `VERCEL_PROJECT_ID` — the Vercel project ID.
4. Push a commit to `main`. Check the **Actions** tab in GitHub for the build
   and deployment result.

The workflow installs Flutter in GitHub Actions, so Flutter does not need to be
installed in Vercel's build environment or configured on your computer to
trigger deployments. Vercel serves the resulting static site. Configure the
backend's CORS allowlist to include the Vercel deployment domain.

## Where to connect the existing backend

- `lib\core\config\api_config.dart` — API host configuration.
- `lib\core\network\api_client.dart` — shared HTTP transport, timeout, JSON
  handling, and API error mapping.
- `lib\features\auth\data\patient_auth_api_repository.dart` — login,
  registration, session identity, email verification, and resend-verification
  request paths and response contracts.
- `lib\features\appointment_history\appointment_history_repository.dart`,
  `lib\features\transaction_history\transaction_history_repository.dart`,
  `lib\features\frames_catalog\frames_catalog_repository.dart`, and
  `lib\features\shell\notification_repository.dart` — feature API adapters.
- `lib\features\profile\patient_profile_repository.dart` — patient contact,
  demographic details, and address used by the dashboard and My Profile.
- `lib\features\auth\application\patient_auth_setup.dart` — wires the shared
  API client and repositories into the app.

Current client routes include:

- `POST /api/patients/login`
- `POST /api/patients/register`
- `GET /api/patients/auth/me`
- `POST /api/patients/verify-email`
- `POST /api/patients/resend-verification`
- `POST /api/patients/forgot-password`
- `POST /api/patients/reset-password`
- `GET /api/appointments` (availability)
- `GET /api/clinic-closures`
- `GET /api/appointments/patient/:patient_id`
- `POST /api/appointments`
- `PATCH /api/appointments/patient/:appointment_id/cancel`
- `GET /api/patients/:patient_id`
- `GET /api/patients/:patient_id/transactions`
- `GET /api/frames`
- Local Flutter Web Try-On assets are served from `web/try_on.html`,
  `web/scripts.js`, `web/face-api.min.js`, and the required SSD/68-point face
  landmark files under `web/models/`. The source script and face-api/model
  files are also kept in the project root; copy any updated versions to `web/`
  before building Flutter Web.
- patient notification list, unread-count, and read-state routes
- `GET /api/patients/support/my-tickets`
- `POST /api/patients/support/tickets`
- `PUT /api/patients/support/tickets/:ticket_id/cancel`
- `GET /api/patients/support/tickets/:ticket_id/messages`
- `POST /api/patients/support/tickets/:ticket_id/messages`
- `PUT /api/patients/support/tickets/:ticket_id/messages/read`

These are not proof that the deployed service implements the same contracts.
Verify each path, request/response shape, patient-ownership checks, and CORS
policy in the online backend before relying on it. Dashboard patient and
appointment requests include the signed-in bearer token; the backend must
verify that the token belongs to the patient ID in each route.

On Flutter Web, the login stores the active session in `sessionStorage` and
also stores it in `localStorage` when Remember Me is selected. The app restores
and validates a stored session with `GET /api/patients/auth/me` before showing
the portal. Logging out clears both browser stores. Browser storage exposes
bearer tokens to JavaScript running on the same origin; use a backend-managed
HttpOnly cookie instead if the API supports that authentication flow. Non-web
builds keep sessions in memory. A successful login response with
`email_verified: false` opens the email-verification page instead of creating
an authenticated session.

## Remaining limitations and registration notes

- Appointment availability, clinic closures, booking requests, patient
  appointment history, and cancellation are connected in the appointments
  page. Booking availability refreshes every five seconds; appointment history
  refreshes every 30 seconds while open. The API must enforce
  availability and patient ownership on the server; client-side slot checks
  are only for display and do not prevent concurrent bookings.
- Support ticket creation, history, cancellation, chat messages, status refresh,
  and optional read receipts use the routes above. The inbox refreshes every
  30 seconds, and an open ticket refreshes its status and messages every five
  seconds. The backend must enforce ticket ownership, patient authorization,
  and ticket status rules.
- Dashboard appointments refresh every 15 seconds; dashboard and profile
  details refresh every 30 seconds. Transaction history refreshes every 30
  seconds, notifications every 20 seconds, and the frames catalog every 60
  seconds while their respective modules are open. These client-side polling
  intervals require the API to remain available and do not replace server-side
  validation.
- Profile updates, password changes, and password reset do not yet have live
  API adapters here.
- Registration now follows the provided HTML contract: it posts the patient's
  name, calculated age, DOB, gender, contact, email, password, and address to
  `POST /api/patients/register`, then opens email verification. The province
  and city/municipality fields are sent as the address library's codes;
  barangay is sent as its displayed name. The API host must use HTTPS and the
  backend must hash passwords securely before storage.
- Forgot password requests a six-digit OTP and resets the password using the
  provided API contract. The backend must enforce OTP expiry and one-time use,
  rate-limit reset requests, and securely hash the new password.
- The frames catalog keeps its Flutter UI visible and opens virtual Try-On in
  an overlay. A minimal same-origin `try_on.html` iframe hosts the browser
  camera/face-detection engine. Camera access requires HTTPS (or localhost),
  browser camera permission, and the Three.js CDN scripts used by the existing
  Try-On script.
- Philippine province, city/municipality, and barangay data is bundled locally
  from `phil-reg-prov-mun-brgy` v1.1.0, matching the library used by the
  provided HTML script. Its barangay data contains some municipality codes
  absent from its city/municipality list, so those entries cannot be selected
  until the source dataset is corrected; the app also omits its single
  blank-named barangay record. Source and package attribution:
  <https://github.com/ejcubillas/phil-reg-prov-mun-brgy> (ISC package license;
  address data credited there to the National Statistical Coordination Board
  and `clavearnel`). The data loads offline; if it needs updating, check the
  source package and its current license/data before replacing it.
- The identity endpoint supplies patient ID, name, email, verification state,
  and account status. Dashboard contact details and My Profile demographics
  and address are loaded from `GET /api/patients/:patient_id`; they remain
  unavailable if that request fails. My Profile follows the HTML integration's
  response handling (`patient`, `data`, or a direct patient object) and common
  name, contact, email, and date-of-birth field aliases. The Edit Profile form
  is prefilled from the same endpoint. Its address fields accept backend values
  directly rather than relying on a partial local address list. The backend
  must enforce patient ownership for this route.

Do not add backend secrets to this Flutter client. API credentials and
privileged operations belong on the server.
