# Stripe billing (hosted mode)

Hosted households pay through Stripe, via the [Pay](https://github.com/pay-rails/pay) gem. Stripe is the system of record: the app keeps a copy of each customer, subscription and charge, and Stripe's webhooks keep that copy current. Appliance installs never talk to Stripe.

## Keys and prices

Set these in the deployment environment (see `.env.example`):

| Variable | What it is |
|---|---|
| `STRIPE_PRIVATE_KEY` (or `STRIPE_SECRET_KEY`) | Secret API key |
| `STRIPE_PUBLISHABLE_KEY` | Publishable key |
| `STRIPE_SIGNING_SECRET` | The webhook endpoint's signing secret (`whsec_...`) |
| `STRIPE_MONTHLY_PRICE_ID`, `STRIPE_ANNUAL_PRICE_ID` | Recurring prices for the two plans. Without them, Checkout builds the $4/month and $35/year prices inline. |

With no secret key, subscribing is simulated in the app and nothing reaches Stripe.

## Webhook endpoint

In the Stripe Dashboard, under **Developers → Webhooks**, add an endpoint at:

```
https://<your-host>/pay/webhooks/stripe
```

Put its signing secret in `STRIPE_SIGNING_SECRET`. A request with a missing or wrong signature is rejected and nothing is stored.

Subscribe the endpoint to these events. Stripe only sends the events an endpoint is subscribed to, and nothing in the app warns you about one that never arrives.

**Access.** Without these, a household can pay and not get in, or stop paying and keep access.

| Event | What the app does |
|---|---|
| `checkout.session.completed` | Records the subscription a Checkout created. This covers a customer who closes the tab before coming back to the app. |
| `customer.subscription.created` | Records a new subscription, and refreshes promotion redemption counts (see below). |
| `customer.subscription.updated` | Updates access from the subscription's status: active, trialing, past due (7-day grace), unpaid, paused, and so on. |
| `customer.subscription.deleted` | Ends access. |
| `invoice.updated` | Re-syncs the subscription when its latest invoice changes, such as when Stripe stops trying to collect. |
| `checkout.session.async_payment_succeeded` | Records the subscription once a delayed payment method, such as a bank debit, clears. You only need this if Checkout offers one. |

**Charges.** These feed the charge list in the operator console.

| Event | What the app does |
|---|---|
| `charge.succeeded`, `charge.updated` | Records a paid or uncaptured charge |
| `charge.failed`, `charge.pending` | Records the failed or pending charge |
| `charge.refunded` | Records a full or partial refund |
| `charge.dispute.created` | Marks the charge as disputed |
| `payment_intent.succeeded` | Records the charge behind a payment |

**Customer email.** Pay sends these emails to the household organizer's address.

| Event | Email |
|---|---|
| `invoice.payment_failed` | Payment declined |
| `invoice.payment_action_required` | Payment needs confirming (3-D Secure) |
| `invoice.upcoming` | Annual renewal reminder |
| `customer.subscription.trial_will_end` | Trial ending |

**Customer records.** Keeps the stored payment method and customer details current: `customer.updated`, `customer.deleted`, `payment_method.attached`, `payment_method.updated`, `payment_method.automatically_updated`, `payment_method.card_automatically_updated`, `payment_method.detached`.

Pay also handles `account.updated`, which is for Stripe Connect. FamilyPlates doesn't use Connect, so leave it off.

## Promotions

A promotion program in the console (`/platform_admin/promotion_programs`) stands for a Stripe promotion code:

1. Create the coupon and the promotion code in Stripe.
2. Create a program in the console with the same customer-facing code and the promotion code's ID (`promo_...`).
3. Assign it to households with a bulk operation (**Assign Approved Promotion**).

A household with an assigned program gets its discount applied at Checkout, without typing anything. The program must be active, inside its start and end dates, and under its redemption limit. Everyone else sees a box at Checkout where they can type a code.

Redemption counts come from Stripe. The count is refreshed from each program's promotion code every time a subscription is created, so codes typed at Checkout count too. A program that reaches its limit stops being applied at Checkout. Stripe enforces the promotion code's own limit separately, so set the limit in both places.

## Managing a household's billing

The household page in the operator console can:

- **Cancel the subscription**, at the end of the period (access lasts until then) or immediately (access ends now, with no refund).
- **Refund a charge**, in full or in part. The default is whatever has not been refunded yet.
- **Comp free months** (1–12). For a paying household, this moves the next Stripe charge back by that many months, and billing resumes on its own. While comped, the subscription shows as trialing. For a household that is not paying, it extends the free trial instead.

Each action needs a reason, which goes in the audit log. Only `owner` and `billing` operators can take these actions. `support` and `privacy` operators see billing but cannot change it.
