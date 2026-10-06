# 🚀 Getting Started & Deployment Guide

This guide covers deploying **FamilyPlates** via **Docker** (recommended for self-hosting and home servers) as well as bare-metal setup for local Ruby development.

---

## 🐳 Quick Start: Docker Deployment (Recommended)

FamilyPlates is packaged as a lightweight, production-ready container powered by Thruster and Puma with embedded SQLite.

### Method 1: Docker Compose (Easiest)

1. **Create or download `docker-compose.yml`:**
   ```yaml
   services:
     familyplates:
       image: ghcr.io/elevate08/familyplates:latest
       container_name: familyplates
       restart: unless-stopped
       ports:
         - "3000:80"
       environment:
         - RAILS_ENV=production
         - "SECRET_KEY_BASE=${SECRET_KEY_BASE:?required - generate one with openssl rand -hex 64}"
         - RAILS_SERVE_STATIC_FILES=true
         - RAILS_LOG_TO_STDOUT=true
       volumes:
         - familyplates_data:/rails/storage

   volumes:
     familyplates_data:
   ```

2. **Generate a Secret Key:**
   ```bash
   # Generate a 64-character random hex string for SECRET_KEY_BASE
   openssl rand -hex 64
   ```

3. **Start the Container:**
   ```bash
   docker compose up -d
   ```

4. **Access the Application:**
   Open [`http://localhost:3000`](http://localhost:3000) (or your server's IP address) in your browser.

---

### Method 2: Docker CLI (`docker run`)

Run FamilyPlates with persistent storage mounted to a local volume:

```bash
docker volume create familyplates_data

docker run -d \
  --name familyplates \
  --restart unless-stopped \
  -p 3000:80 \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e RAILS_SERVE_STATIC_FILES=true \
  -e RAILS_LOG_TO_STDOUT=true \
  -v familyplates_data:/rails/storage \
  ghcr.io/elevate08/familyplates:latest
```

---

## 🛠️ Environment Variables Reference

| Variable | Default | Description |
| :--- | :--- | :--- |
| `SECRET_KEY_BASE` | *(Required in prod)* | 64-byte random key used for encrypted cookies and credentials. |
| `RAILS_ENV` | `production` | Environment mode (`production`, `development`, `test`). |
| `RAILS_SERVE_STATIC_FILES` | `true` | Serves compiled CSS/JS assets directly from the application. |
| `RAILS_LOG_TO_STDOUT` | `true` | Emits application logs to standard out for Docker/K8s log collection. |
| `PORT` | `80` | Internal listening port inside the container. |
| `APP_HOST` | *(None)* | Public hostname, such as `plates.example.com`. No scheme, no path. |
| `SMTP_ADDRESS` | *(None)* | Mail server hostname. Optional on an appliance. |
| `SMTP_PORT` | `587` | Mail server port. |
| `SMTP_USER_NAME` | *(None)* | Mail server username, when the server requires one. |
| `SMTP_PASSWORD` | *(None)* | Mail server password. Required when a username is set. |
| `MAILER_DEFAULT_FROM` | `noreply@familyplates.app` | From address on sign-in mail. |

### Public hostname and email

A home server on the LAN does not set `APP_HOST` or any `SMTP_*` variable. It starts without them.

If you expose your appliance on the internet, set `APP_HOST` to its public hostname. The app then allows only that host, and any mail it sends links to it. Email is optional on an appliance, which signs in with profiles, PINs and passwords.

If you set any SMTP variable, the app will not start until `SMTP_ADDRESS` is set. If you set `SMTP_USER_NAME`, you must also set `SMTP_PASSWORD`.

The health check at `/up` stays reachable by the container's own address so Docker can probe it.

```yaml
environment:
  - APP_HOST=plates.example.com
  - SMTP_ADDRESS=smtp.example.com
  - SMTP_PORT=587
  - SMTP_USER_NAME=mailer
  - SMTP_PASSWORD=replace-me
  - MAILER_DEFAULT_FROM=noreply@plates.example.com
```

The published image is the **appliance** edition. It doesn't include the hosted service's billing, sign-up or operator console, and it refuses to start with `FAMILYPLATES_MODE=hosted`. See [Editions](editions.md).

### External Authentication & Single Sign-On (Optional)

All external identity providers are disabled by default. Configure these variables to enable Google, generic OpenID Connect, or trusted reverse proxy headers:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `AUTH_GOOGLE_ENABLED` | `false` | Enable Google OAuth sign-in (`true` / `false`). |
| `GOOGLE_CLIENT_ID` | *(None)* | Google OAuth 2.0 Client ID. |
| `GOOGLE_CLIENT_SECRET` | *(None)* | Google OAuth 2.0 Client Secret. |
| `AUTH_OIDC_ENABLED` | `false` | Enable generic OpenID Connect / SSO (`true` / `false`). |
| `OIDC_ISSUER` | *(None)* | OIDC Issuer URL (e.g. `https://auth.example.com`). Required: sign-in checks every ID token against it, and endpoints are discovered from it. |
| `OIDC_JWKS_URL` | *(None)* | The provider's signing-key URL. Only needed when the provider has no discovery document. |
| `OIDC_CLIENT_ID` | *(None)* | OIDC Client ID. |
| `OIDC_CLIENT_SECRET` | *(None)* | OIDC Client Secret. |
| `OIDC_DISPLAY_NAME` | `Single Sign-On` | Button label for SSO on sign-in screen (e.g. `Authentik` or `Authelia`). |
| `AUTH_FORWARD_AUTH_ENABLED` | `false` | Enable trusted reverse proxy forward-auth (`true` / `false`). |
| `FORWARD_AUTH_TRUSTED_PROXIES` | `127.0.0.1,::1` | The reverse proxy's own address (a single IP), comma-separated if there is more than one. Network ranges (such as `10.0.0.0/8`) are ignored, and logged at startup. See the note below. |
| `FORWARD_AUTH_EMAIL_HEADERS` | `Remote-Email` | The header that carries the user's email. `Remote-Email` is what Authelia sends; other proxies use other names (see the table below), so set this to your proxy's header. To accept several, list them comma-separated; the first one present is used. The proxy must overwrite or strip every header the app reads. See the note below. |
| `FORWARD_AUTH_USER_HEADERS` | *(None)* | The header that carries a stable user ID. By default no user ID header is read and the email is the ID. Set it only if your proxy sends a stable ID header (see the table below). The proxy must overwrite or strip every header listed. |
| `FORWARD_AUTH_NAME_HEADERS` | `Remote-Name` | The header that carries the display name. Same rule: the proxy must overwrite or strip every header listed. |
| `FORWARD_AUTH_LOGOUT_URL` | *(None)* | Optional URL to redirect to on sign-out (e.g. proxy SSO logout page). |

**Headers each proxy sends.** These are the names in each project's own documentation (checked October 2026; check them again against your proxy's version). Authelia's email and name headers are the app's defaults; no proxy's user ID header is, so set `FORWARD_AUTH_USER_HEADERS` if you want one.

| Proxy | `FORWARD_AUTH_EMAIL_HEADERS` | `FORWARD_AUTH_USER_HEADERS` | `FORWARD_AUTH_NAME_HEADERS` |
| :--- | :--- | :--- | :--- |
| [Authelia](https://www.authelia.com/integration/trusted-header-sso/introduction/) | `Remote-Email` (default) | `Remote-User` (not read unless set) | `Remote-Name` (default) |
| [authentik](https://docs.goauthentik.io/add-secure-apps/providers/proxy/) proxy provider | `X-authentik-email` | `X-authentik-uid` (a hashed ID) or `X-authentik-username` | `X-authentik-name` |
| [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview) | `X-Forwarded-Email` | `X-Forwarded-User` (not read unless set) | `X-Forwarded-Preferred-Username` |
| [Tailscale Serve](https://tailscale.com/kb/1312/serve) | `Tailscale-User-Login` | none sent (leave unset; the email is the ID) | `Tailscale-User-Name` |

- **authentik does not send `Remote-*` headers.** Earlier versions of this guide said it did. If you used authentik with the defaults, forward-auth never signed anyone in, because `Remote-Email` was never set. Set the three variables above.
- **Upgrading: Authelia and oauth2-proxy installs.** Earlier versions read `Remote-User` (and `X-Forwarded-User`) as the user ID by default; this version reads no user ID header unless you set one. Set `FORWARD_AUTH_USER_HEADERS=Remote-User` for Authelia, or `FORWARD_AUTH_EMAIL_HEADERS=X-Forwarded-Email` together with `FORWARD_AUTH_USER_HEADERS=X-Forwarded-User` for oauth2-proxy, to keep each person's existing sign-in identity. If you do not, each person gets a second sign-in identity the first time they sign in after the upgrade, keyed by their email. That is harmless: it is the same account (matched by email), sign-in works as before, and the person sees one extra forward-auth entry under their connected sign-in methods. The old identity is simply no longer used. A user ID header is optional: skip it, and the email is the ID.
- **Tailscale** sends identity headers only for requests from your tailnet (not Funnel), and removes any it finds on an incoming request. It sends no user ID header, so leave `FORWARD_AUTH_USER_HEADERS` unset.
- **Changing a person's email.** When the user ID header names an identity the app already linked to an account, and that account's email (compared without regard to case) is not the email the proxy sent, the sign-in is refused and `[auth] forward_auth_identity_email_mismatch` is logged, without any address. This applies only if you set `FORWARD_AUTH_USER_HEADERS`. Sign-in stays refused while the app account's email and the provider's email differ, and no order of changes avoids that gap, so change both together, and expect the person to be refused in between. Without a user ID header the email is the ID, so a changed email at the provider signs the person into a new account instead.

**Forward-auth trusted proxies.** The app does not use `request.remote_ip` for this check, because that value comes from `X-Forwarded-For`, which a client can set. It checks the hop that connected to the app: the TCP peer address, except when that peer is the loopback address and the request has an `X-Forwarded-For` header, in which case it checks the last entry of that header. A blank or unreadable entry, or one that is an address range, is not trusted. Identity headers from a hop that is not trusted are ignored: the request goes on through normal sign-in.

- **Docker image.** Forward-auth is supported with the Docker image, where requests arrive through Thruster: the TCP peer is loopback, and Thruster adds the address that connected to it as the last `X-Forwarded-For` entry. Puma also listens on port 3000 inside the container; a connection there is checked by its own address. Set `FORWARD_AUTH_TRUSTED_PROXIES` to your reverse proxy's single address as the app container sees it (give the proxy container a fixed IP), not a network range: a range includes the bridge gateway and every other container on that network. Range entries (any prefix shorter than `/32` for IPv4 or `/128` for IPv6) are ignored, and the app logs `[auth] FORWARD_AUTH_TRUSTED_PROXIES ignored entries: <entry> (range)` at startup (an entry that is not an IP address, such as a hostname, is ignored and logged the same way, as `(not an IP address)`), so an install that still lists one stops accepting forward-auth until the proxy's single address is listed. A bare address, or one with an explicit `/32` or `/128`, works. Keep the app's ports reachable only from the proxy.
- **Proxy on the Docker host.** Publish the port on loopback only (`127.0.0.1:3000:80`). Find the address the container sees for the proxy from the Docker side (for example with `docker network inspect`, or the gateway of the network the container is on) and trust that single address. The `forward_auth_untrusted_peer peer=<ip>` log line only confirms which address requests from the proxy arrive with; do not trust an address just because it appears there, since any client's request can be the one logged. Connections relayed by Docker's userland proxy share that address, so do not publish the port on other interfaces while forward-auth is on. Trusting the bridge gateway address trusts every process on the Docker host, and any container whose traffic reaches the app through that gateway, so do this only on a host where every local user and service is trusted. Otherwise run the proxy as a container with a fixed address.
- **No Thruster.** Running `rails server` directly behind a proxy on the same host is not supported for forward-auth. The last `X-Forwarded-For` entry is then whatever the proxy forwarded, which can be the client's address.
- **Identity headers.** The proxy must overwrite or strip every identity header the app reads (the email, user ID and name headers above, whichever names you set), not only the ones it sets. A user who is signed in to the proxy can add headers to their own request. By default the app reads one header each for email, user ID and name and ignores any other, but a header it does read that the proxy does not set or strip is one a user can choose the value of. If you list several headers in one variable, the first one present wins, so the proxy must set or strip every listed header. If you set a user ID header the proxy does not set, a user can add it: the app refuses a sign-in when the user ID names an account whose email differs from the email the proxy sent, but have the proxy strip it anyway.
- **Ignored identity headers.** When identity headers arrive from a hop that is not trusted, the app ignores them and logs `[auth] forward_auth_untrusted_peer peer=<ip>` (`peer=unparseable` if the address could not be read, `peer=range:<address>/<prefix>` if it was an address range). It never logs header values.

## Running the tests

```bash
bin/rails test          # models, controllers, integration - fast, no browser
bin/rails test:system   # browser-driven, needs Chrome or Chromium
```

System tests are excluded from `bin/rails test` on purpose, so the common case
stays quick. They drive a real browser and **fail on anything the browser logs at
SEVERE** — an uncaught exception, a Stimulus controller that will not register, a
script the Content Security Policy refuses. That check is what catches the class
of defect a request test cannot see, since request tests render HTML but never
run it.

Point `CHROME_BIN` at your browser if it is not the default:

```bash
CHROME_BIN=/usr/bin/chromium bin/rails test:system
```

The Playwright suite runs through `bin/e2e`, with the browser in the pinned
Playwright Docker image so screenshots match CI. It also crawls every page as
every kind of visitor. See the Testing section of the [README](../README.md)
for running it without Docker, re-recording screenshots, and what a new route
needs.

```bash
bin/e2e                 # Playwright, needs Docker
bin/ci                  # everything CI runs
```


---

## 💻 Local Bare-Metal Development (Developers)

If you are developing or contributing to FamilyPlates directly:

### 1. Prerequisites
* **Ruby:** `4.0.x` or `3.4.x`
* **SQLite:** `3.40+`
* **libvips:** Required for image processing and recipe attachments

### 2. Local Setup
```bash
# Clone the repository
git clone https://github.com/Elevate08/familyplates.git
cd familyplates

# Install dependencies
bundle install

# Setup database & migrations
bin/rails db:setup

# Start development server (Puma + Tailwind CSS watcher)
bin/dev
```

Visit [`http://localhost:3000`](http://localhost:3000) in your browser.

### 3. Running Automated Tests
```bash
bin/rails test
```

See [Running the tests](#running-the-tests) for the browser suites.

---

## 🔐 First-Boot Onboarding

When launching FamilyPlates for the first time, the 4-step **Onboarding Wizard** (`/onboarding`) guides you through:
1. **Household Naming:** Set your family kitchen name.
2. **Family Member Roster:** Add family members and set 4-digit security PINs for Organizer profiles.
3. **Starter Recipes:** Select curated starter recipes to populate your vault.
4. **On-Hand Inventory (Pantry Shield):** Confirm kitchen basics to keep your weekly supermarket grocery lists clean.

Next, follow the **[Universal Calendar Subscriptions Guide](universal-calendar-subscriptions)** to connect your shared family calendar!
