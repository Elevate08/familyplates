# Adversarial Security Review: Gemini Agent Report

## Scope: Data Ingress and Egress
- **Target Areas:**
  - Recipes, recipe imports, and `RecipeScraper` (`app/services/recipe_scraper.rb`, SSRF, parsing)
  - `OutboundUrlPolicy` (`app/services/outbound_url_policy.rb`)
  - Meal plans and meal plan slots (`MealPlansController`, `MealPlanSlotsController`, `MealPlan`, `MealPlanSlot`)
  - Pantry items (`PantryItemsController`, `PantryItem`, and `pantry_icon_tag` in `ApplicationHelper`)
  - Grocery lists (`GroceryListsController`, `GroceryList`, `IngredientAggregator`)
  - Calendar feeds (`CalendarFeedsController`, `CalendarFeedService`, token access)
  - Account data export (`AccountDataController`, `HouseholdExport`)
  - Activity events (`ActivityEventsController`, `ActivityEvent`)
  - Home and Onboarding (`HomeController`, `OnboardingController`)
  - Active Storage uploads and image handling (`Recipe`, `acceptable_image`, file extension and Marcel mime validation)
  - JavaScript controllers in `app/javascript/controllers/` (DOM XSS, unsafe HTML)
  - Content Security Policy (`config/initializers/content_security_policy.rb`)

---

## Findings Summary

| ID | Severity | File | Attack / Vulnerability Description | Status | Commit / Notes |
|:---|:---|:---|:---|:---|:---|
| FP-SEC-01 | High | `app/services/outbound_url_policy.rb` | SSRF filter bypass via IPv4-compatible IPv6 addresses (`::127.0.0.1`), 6to4 encapsulation (`2002::/16`), deprecated site-local/reserved IPv6 ranges (`fec0::/10`, `::/96`, `64:ff9b:1::/48`), and arbitrary destination port reachability (attacking internal Redis 6379, SMTP 25, etc.). | Fixed | Commit `c490107` |
| FP-SEC-02 | Medium | `app/services/recipe_scraper.rb` | Image URL scheme smuggling: `absolutize` permitted `data:` and `javascript:` URIs extracted from scraped pages without scheme sanitization. Malicious pages could smuggle inline SVG/JS into imported recipe images. | Fixed | Commit `d2f2841` |
| FP-SEC-03 | High | `app/models/recipe.rb`, `app/views/recipes/show.html.erb` | Stored XSS / URL scheme execution: `source_url` and `image_url` allowed dangerous schemes (`javascript:`, `data:`, `vbscript:`, `file:`) that execute in the browser upon click or image render. Solved via scheme validation and `safe_source_url` / `safe_url?` guards. | Fixed | Commit `7fbc747` |
| FP-SEC-04 | High | `app/models/recipe.rb` | Active Storage file content spoofing: `acceptable_image` previously only inspected the client-supplied `content_type` header without verifying file extension or actual byte stream content via Marcel, permitting polyglot HTML/SVG uploads disguised as JPEG. | Fixed | Commit `7fbc747` |
| FP-SEC-05 | Low | `app/views/recipes/show.html.erb` | Reverse tabnabbing & referrer leak on external recipe source links: `rel: "noopener"` updated to `rel: "noopener noreferrer"`. | Fixed | Commit `7fbc747` |

---

## Detailed Findings and Fixes

### 1. SSRF Filter Bypasses in `OutboundUrlPolicy` (FP-SEC-01)
- **Vulnerability:**
  `OutboundUrlPolicy.check!` validates outbound URLs for recipe importing. However:
  1. It allowed connections to arbitrary TCP ports (e.g. `http://public-host.com:6379` or `http://public-host.com:25`), exposing internal service ports on machines with dual-homed or exposed DNS.
  2. It only blocked standard IPv4-mapped IPv6 (`::ffff:0:0/96`), but failed to block IPv4-compatible IPv6 addresses (`::127.0.0.1`, `::192.168.1.1` in `::/96`), which resolve to blocked IPv4 addresses on dual-stack hosts.
  3. It did not block 6to4 prefix `2002::/16`, where IPv4 addresses are encoded in bits 16-47 (e.g. `2002:7f00:0001::` for `127.0.0.1`).
  4. It omitted deprecated site-local (`fec0::/10`) and local IPv4/IPv6 translation ranges (`64:ff9b:1::/48`).
- **Fix:**
  - Enforced `ALLOWED_PORTS = [80, 443, 8080, 8443]`.
  - Added unpacking for `ipv4_compat?` and embedded IPv4 within 6to4 (`2002::/16`).
  - Added blocked ranges: `IPAddr.new("::/96")`, `IPAddr.new("fec0::/10")`, `IPAddr.new("64:ff9b:1::/48")`.
- **Test Proof:**
  - `test/services/outbound_url_policy_test.rb`:
    - `test_refuses_IPv4-compatible_IPv6_spellings_of_blocked_addresses`
    - `test_refuses_6to4_addresses_encapsulating_blocked_IPv4_space`
    - `test_refuses_non-web_ports_such_as_redis_or_smtp`

---

### 2. Image Scheme Smuggling in `RecipeScraper` (FP-SEC-02)
- **Vulnerability:**
  When extracting images from Schema.org JSON-LD or Microdata (`og:image`, `image`, `ImageObject`), `RecipeScraper#absolutize` joined relative paths against `base_url` using `URI.join`. However, if the page declared `data:image/svg+xml;base64,...` or `javascript:...`, `URI.join` accepted the scheme and returned it as a valid image URL.
- **Fix:**
  - Enforced `['http', 'https'].include?(uri.scheme) && uri.host.present?` in `RecipeScraper#absolutize`.
  - Non-HTTP/HTTPS schemes return `nil` and are rejected during scraping.
- **Test Proof:**
  - `test/services/recipe_scraper_test.rb`:
    - `test_rejects_data:_and_javascript:_schemes_in_extracted_images`

---

### 3. Stored XSS / Malicious URL Schemes in Recipes (FP-SEC-03)
- **Vulnerability:**
  `Recipe` instances accept user-entered `source_url` and `image_url`. If an attacker input `source_url = "javascript:alert(1)"`, rendering `<%= link_to @recipe.source_url, ... %>` generated `<a href="javascript:alert(1)">`, executing arbitrary script in the victim's session when clicked.
- **Fix:**
  - Added `validate_url_schemes` in `app/models/recipe.rb` that blocks forbidden schemes (`javascript:`, `vbscript:`, `data:`, `file:`).
  - Added `safe_source_url` method on `Recipe` that ensures only valid `http` and `https` URLs with hosts are rendered in `app/views/recipes/show.html.erb`.
  - `display_image_url` strictly checks `safe_url?` before returning non-blob URLs.
- **Test Proof:**
  - `test/models/recipe_test.rb`:
    - `test_rejects_dangerous_URL_schemes_for_source_url_and_image_url`
    - `test_display_image_url_falls_back_to_default_if_image_url_has_an_unsafe_scheme`
  - Integration tests in `test/integration/stored_xss_test.rb` continue to verify that attribute breakout is impossible.

---

### 4. Active Storage File Extension and Magic Byte Inspection (FP-SEC-04)
- **Vulnerability:**
  `Recipe#acceptable_image` previously only inspected `blob.content_type`, which is taken directly from the client request's `Content-Type` header. An attacker could upload an HTML, SVG, or executable payload with a forged `Content-Type: image/jpeg` header and `.html` filename.
- **Fix:**
  - Enforced `ALLOWED_IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp]`.
  - Added inspection of actual file byte signatures via `Marcel::MimeType.for(io, name: blob.filename.to_s)` before record commit, catching polyglots and disguised files.
- **Test Proof:**
  - `test/models/recipe_test.rb`:
    - `test_rejects_an_upload_with_non-image_extension_even_if_content_type_header_is_forged`
    - `test_rejects_an_upload_with_image_extension_when_content_is_actually_HTML_or_SVG`

---

### 5. Reverse Tabnabbing Defense-in-Depth (FP-SEC-05)
- **Hardening:**
  - Updated `target: "_blank"` link on `app/views/recipes/show.html.erb` from `rel: "noopener"` to `rel: "noopener noreferrer"` to prevent referrer leakage of household query parameters or internal IDs to external recipe sources.

---

## Audited Areas Found Sound

1. **Calendar Feeds (`CalendarFeedsController`, `CalendarFeedService`):**
   - High-entropy tokens (`calendar_feed_token`) generated via `has_secure_token` and indexed uniquely.
   - Routes constrain token format to `/[a-zA-Z0-9_-]+/`, preventing empty or path traversal patterns.
   - Member filtering in `CalendarFeedsController#member` is strictly scoped through `@household.family_members.find_by(id: params[:member_id])`, preventing cross-household IDOR.
   - RFC 5545 output escaping (`CalendarFeedService#escape_text`) strips/escapes CR, LF, semicolons, and commas, preventing iCalendar injection.
   - HTTP caching sets `public: false` in `Cache-Control` (`private, max-age=0, must-revalidate`), preventing intermediate caching proxies from leaking household calendar feeds.

2. **Meal Plan Slots & Planner Loading (`MealPlanSlotsController`, `MealPlanSlot`):**
   - `MealPlanSlot` validates that `recipe` and `family_member` belong to the current household (`recipe_belongs_to_household`, `cook_belongs_to_household`).
   - Slot movement and leftover assignment validate tenant scoping on leftover sources (`eligible_leftover_source?` checks `source.meal_plan&.household_id == meal_plan.household_id`).
   - `MealPlanSlotsController` requires admin role for slot mutations.

3. **Pantry Items & Helpers (`PantryItemsController`, `ApplicationHelper`):**
   - `PantryItemsController` scopes all queries to `current_household.pantry_items`.
   - `pantry_icon_tag` in `ApplicationHelper` sanitizes custom emoji via `emoji_span`, which uses `tag.span` to HTML-escape content. Only static, hard-coded SVG constants from `HAND_DRAWN_PANTRY_ICONS` are rendered raw.

4. **Account Data Export (`AccountDataController`, `HouseholdExport`):**
   - `AccountDataController` requires admin authorization (`require_admin`).
   - `HouseholdExport` strictly whitelists attributes via `.slice(...)`, omitting `join_code`, `calendar_feed_token`, `password_digest`, and session tokens.

5. **JavaScript Stimulus Controllers (`app/javascript/controllers/`):**
   - Audited all uses of `innerHTML`, `outerHTML`, and DOM manipulation in `date_picker_controller.js`, `ingredient_autofill_controller.js`, `pantry_item_form_controller.js`, and `tag_picker_controller.js`.
   - Free text fields are set via `textContent` or `replaceChildren(el(...))`, preventing DOM XSS.

6. **Content Security Policy (`config/initializers/content_security_policy.rb`):**
   - `script_src` withholds `unsafe-inline` and `unsafe-eval`.
   - Dynamic inline scripts carry session-consistent nonces.
   - `object_src :none`, `default_src :self`, `frame_ancestors :self`, `base_uri :self`.
   - Form actions are strictly constrained to `:self`, Google, Apple, and Stripe (hosted mode only).

---

## Outside My Scope

No active vulnerabilities found outside scope during this review.
