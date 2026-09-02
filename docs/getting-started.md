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
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | *(Required for Google Calendar)* | Encrypts the stored Google service account key. `openssl rand -hex 32`. Must not change once set. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | *(Required for Google Calendar)* | Paired with the key above. `openssl rand -hex 32`. Must not change once set. |
| `RAILS_ENV` | `production` | Environment mode (`production`, `development`, `test`). |
| `RAILS_SERVE_STATIC_FILES` | `true` | Serves compiled CSS/JS assets directly from the application. |
| `RAILS_LOG_TO_STDOUT` | `true` | Emits application logs to standard out for Docker/K8s log collection. |
| `PORT` | `80` | Internal listening port inside the container. |

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
bundle exec rails test
```

---

## 🔐 First-Boot Onboarding

When launching FamilyPlates for the first time, the 4-step **Onboarding Wizard** (`/onboarding`) guides you through:
1. **Household Naming:** Set your family kitchen name.
2. **Family Member Roster:** Add family members and set 4-digit security PINs for Organizer profiles.
3. **Starter Recipes:** Select curated starter recipes to populate your vault.
4. **On-Hand Inventory (Pantry Shield):** Confirm kitchen basics to keep your weekly supermarket grocery lists clean.

Next, follow the **[Google Calendar Sync Guide](google-calendar-integration)** to connect your shared family calendar!
