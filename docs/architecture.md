# 🏗️ Architecture & Technology Stack

FamilyPlates is built with modern Rails best practices, adhering to simplicity, low maintenance overhead, and fast execution.

---

## 💻 Tech Stack

* **Framework:** Ruby on Rails 8.1.3
* **Language:** Ruby 4.0 / 3.4
* **Frontend:** Hotwire (Turbo 8 + Stimulus), Tailwind CSS v4, Propshaft Asset Pipeline
* **Database:** SQLite 3 with WAL mode
* **Background Jobs:** Solid Queue (`ActiveJob` backend)
* **Caching & WebSockets:** Solid Cache & Solid Cable
* **Google Integration:** Google Calendar API v3 via `google-apis-calendar_v3` and `googleauth` Service Account JWT authentication

---

## 🗄️ Core Data Models

```mermaid
erDiagram
    Household ||--o{ FamilyMember : has
    Household ||--o{ Recipe : owns
    Household ||--o{ MealPlan : tracks
    Household ||--o{ PantryItem : maintains
    Household ||--o{ IngredientAisleMapping : learns

    User ||--o{ Identity : has
    User ||--o{ Session : holds
    User ||--o{ FamilyMember : claims

    MealPlan ||--o{ MealPlanSlot : contains
    Recipe ||--o{ RecipeIngredient : contains
    Recipe ||--o{ RecipeRequest : receives
    FamilyMember ||--o{ RecipeRequest : makes
    FamilyMember ||--o{ MealPlanSlot : cooks
    Recipe ||--o{ MealPlanSlot : fills

    Household {
        string id PK "UUID"
        string join_code "unique"
        datetime onboarded_at "nullable"
    }
    User {
        string id PK "UUID"
        string email "unique, NOCASE"
        string password_digest "nullable"
        datetime verified_at "nullable"
    }
    Identity {
        string id PK "UUID"
        string user_id FK "UUID"
        string provider
        string uid
    }
    Session {
        string id PK "UUID"
        string user_id FK "UUID"
        string token "unique"
        string kind
        datetime last_active_at
        datetime expires_at "nullable"
    }
    FamilyMember {
        string id PK "UUID"
        string household_id FK "UUID"
        string user_id FK "UUID, nullable"
    }
    Recipe {
        integer id PK
        string household_id FK "UUID"
    }
    MealPlan {
        integer id PK
        string household_id FK "UUID"
    }
    PantryItem {
        integer id PK
        string household_id FK "UUID"
    }
    IngredientAisleMapping {
        integer id PK
        string household_id FK "UUID, nullable"
    }
    MealPlanSlot {
        integer id PK
        string family_member_id FK "UUID, nullable"
    }
    RecipeRequest {
        integer id PK
        string family_member_id FK "UUID"
    }
```

---

## 🔒 Security & Authentication Model

* **Account & Identity Boundary:** Phase 1 establishes the account boundary via `User`, `Identity`, and `Session` models. `User` holds a nullable `password_digest` for appliance mode while keeping hosted mode passwordless; `Identity` supports multiple login credentials (email, OAuth, passkeys) per user; `Session` provides revocable browser/kiosk session tokens. `FamilyMember.user_id` is an optional foreign key with a per-household uniqueness constraint, allowing family members to attach personal accounts while preserving email-free profiles for children.
* **Profile Authentication:** Daily interaction remains centered on family-member profiles chosen at `/select_profile`. Organizer (`admin`) profiles require a 4-digit PIN; ordinary member profiles are deliberately open for one-tap switching on a shared kitchen tablet.
* **PIN Storage:** PINs are stored as bcrypt digests (`family_members.pin_digest`) via `has_secure_password`, and cannot be read back off a record. Entry is rate limited per IP and per profile across both entry paths, and comparison is constant-time.
* **Cookie Sessions:** The active profile is held in a signed, `HttpOnly`, `SameSite=Lax` cookie, marked `Secure` when the request arrives over TLS. **A LAN deployment without TLS sends this cookie in the clear** — anyone exposing the app beyond a trusted network should terminate TLS in front of it and enable `config.force_ssl`.
* **Session Secret:** `SECRET_KEY_BASE` signs that cookie, so a predictable value lets anyone forge a session. The app refuses to boot in production on a known placeholder or a value under 32 characters.
* **Credentials Protection:** The Google service account key is encrypted at rest with Active Record encryption, keyed from `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`, and is never rendered back into the settings page. Key files remain excluded from git tracking.
