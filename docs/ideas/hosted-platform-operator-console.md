# Hosted Platform Operator Console

## Problem Statement

How might we give the platform operator a secure, trustworthy command center for understanding and managing every hosted household—without exposing administrative capabilities to ordinary household users or relying on impersonation?

The current household admin area is scoped to one household. Hosted FamilyPlates needs a separate platform-operator experience that can scale to 1,000+ US households and support customer health, support, billing, promotions, privacy requests, and account lifecycle operations.

## Recommended Direction

Build one private Hosted Platform Operator Console with three connected layers: an operator cockpit, trust/lifecycle operations, and a meaningful product-activity foundation.

The console uses a separate `PlatformAdmin` identity and session boundary, initially with one owner role and required MFA. It is read-only by default. Household detail pages show privacy-safe metadata and health indicators first; explicit support, billing, export, suspension, and deletion actions are isolated behind confirmation and audit logging. No impersonation is needed.

The platform should maintain meaningful activity events that power operator health views, a customer-visible household activity history, and support diagnosis. Customer support should be an in-app persistent conversation attached to the household, with internal notes kept separate. Billing remains provider-authoritative, while FamilyPlates tracks entitlement and operational state.

## Key Assumptions to Validate

- [ ] Meaningful domain events accurately represent household engagement better than login timestamps alone; validate against real support cases and early hosted usage.
- [ ] A single operator can manage support manually through persistent in-app conversations before assignment queues, automation, or a full helpdesk are needed.
- [ ] Provider-backed billing synchronization can represent trial, payment, grace-period, cancellation, promotion, and entitlement states without unsafe local overrides.
- [ ] Export and deletion workflows can identify and remove/anonymize household data across live records, integrations, support history, caches, analytics, and backup-retention boundaries.
- [ ] The documented deletion and backup policy is precise enough for the initial US launch and can be localized as geographic coverage expands.

## MVP Scope

### Security and access

- Separate `PlatformAdmin` accounts and sessions, not attached to households.
- Initial owner-only role, with a model that can later support support, billing, and privacy roles.
- MFA, session/device visibility and revocation, authentication rate limiting, and new-session alerts.
- Private, unadvertised route; route secrecy is not treated as a security control.

### Operator cockpit

- Searchable household directory across name, email, and user.
- Filters and predefined views for onboarding, activity, trial, billing, promotion, suspension, and deletion state.
- At-a-glance household metrics: members, recipes, meal plans, pantry items, calendar integration, and recent meaningful activity.
- Household detail view with privacy-safe defaults and intentional access to sensitive content.

### Support and history

- Persistent in-app support conversations with open, waiting-on-customer, waiting-on-support, and resolved states.
- Email notifications linking back to authenticated conversations.
- Internal support notes and controlled operational tags, separate from customer-visible messages.
- Customer-visible activity history for meaningful planner, recipe, pantry, account, and system actions, including the acting family member when applicable.

### Billing and lifecycle

- Provider-synchronized billing and entitlement view: trialing, active, past due, grace period, canceled-period-end, expired, payment failure, refund/chargeback, promotion, and manual override.
- Audited safe actions such as trial extension, approved promotion assignment, cancellation at period end, and temporary entitlement.
- Named promotion programs with eligibility, dates, limits, discount/trial extension, attribution, and redemption reporting.
- Customer-requested and support-assisted exports as expiring ZIPs of structured JSON, excluding credentials, tokens, private keys, internal notes, and payment-card data.
- Customer deletion requests, operator-controlled permanent deletion, and reversible household suspension.
- Suspended customers can authenticate but see a dedicated suspension page with a support link.

### Audit, privacy, and operations

- Audit all platform-admin mutations and sensitive reads such as household detail access, exports, and deletion workflows.
- Lightweight security-event history and alerts for MFA/login activity, exports, deletion, and suspicious authentication failures.
- Documented policy for live data, backups, billing records, integrations, support history, and minimal retained audit metadata.

## Not Doing (and Why)

- **Household impersonation** — unnecessary for the current support model and creates a high-risk access path.
- **General bulk mutations in the first release** — easy to misuse; revisit after the base console is trusted. The first candidate should be guarded promotion/tag operations, never bulk permanent deletion.
- **Automated lifecycle campaigns** — first establish reliable activity and billing signals.
- **Anomaly detection and automated fraud blocking** — defer until there is meaningful operational data.
- **Full multi-role administration** — design the boundary now, but one owner role is enough initially.
- **Full CRM/helpdesk behavior** — persistent in-app support threads are sufficient for the first operator.
- **Omnichannel support and file attachments** — add only when support volume demonstrates the need.
- **Casual browsing of household content** — privacy-safe metadata-first presentation is the default.

## Open Questions

- What exact household data belongs in exports, and what retention exceptions are required for billing, abuse, and legal records?
- What backup retention period and restore/deletion guarantees will the hosted deployment use?
- Which email provider and notification policy should support conversations use?
- Which billing-provider operations are safe to expose directly versus linking to the provider portal?
- What is the minimum MFA/recovery experience for the initial platform owner?
- Which activity events should be retained for customer history versus private diagnostics?
- When should a household be considered inactive or at risk, and should those labels be configurable?
