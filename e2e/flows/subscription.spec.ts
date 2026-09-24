import { test, expect } from "@playwright/test";
import { resetDatabase, preparePageForSnapshot, fastSignIn } from "../support/test-helpers";

test.describe("Stripe & Subscriptions (Hosted Mode)", () => {
  // ---------------------------------------------------------------------------
  // Level 1: In-App Billing UI, Pricing Tiers, and Subscription Lifecycle Flow
  // Runs 100% offline, deterministically, with zero external dependencies.
  // ---------------------------------------------------------------------------
  // @card-23.5 @card-23.9
  test("Level 1: subscription dashboard renders pricing tiers, handles subscription & cancellation", async ({
    page,
    request
  }) => {
    // Reset database into hosted mode
    await resetDatabase(request, { mode: "hosted" });

    await fastSignIn(page, "Dad");
    await page.goto("/subscription");
    await page.waitForLoadState("domcontentloaded");

    // 1. Verify pricing table header and plans
    await expect(page.locator("h1")).toContainText("Subscription & Billing");
    await expect(page.locator("body")).toContainText("Annual Plan");
    await expect(page.locator("body")).toContainText("Monthly");

    // 2. Visual appearance snapshot of the pricing tiers
    await preparePageForSnapshot(page);
    await expect(page).toHaveScreenshot("subscription-pricing-plans.png");

    // 3. Subscribe to Annual Plan (simulated in-app flow)
    await page.route("**/subscription*", async (route) => {
      if (route.request().method() === "POST") {
        const url = new URL(route.request().url());
        url.searchParams.set("simulate", "true");
        await route.continue({ url: url.toString() });
      } else {
        await route.continue();
      }
    });

    const subscribeButton = page.locator('input[value*="Annual"], button:has-text("Annual")').first();
    await subscribeButton.click();

    // 4. Verify Active Subscription status
    await expect(page.locator("body")).toContainText("Active Subscription");
    await expect(page.locator("body")).toContainText("Successfully subscribed");

    // 5. Verify Cancel Subscription flow
    page.on("dialog", (dialog) => dialog.accept());
    const cancelButton = page.locator('input[value*="Cancel Subscription"], button:has-text("Cancel Subscription")').first();
    await expect(cancelButton).toBeVisible();
    await cancelButton.click();

    const confirmModalBtn = page.locator("#app-confirm-submit");
    if (await confirmModalBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await confirmModalBtn.click();
    }

    // 6. Verify canceled state with retained access notice
    await expect(page.locator("body")).toContainText("Your subscription has been canceled");
    await expect(page.locator("body")).toContainText("Cancels on");
  });

  // ---------------------------------------------------------------------------
  // Level 2: Real Stripe Checkout Sandbox Flow
  // Requires STRIPE_PRIVATE_KEY=sk_test_... and ENABLE_REAL_STRIPE_TESTS=true
  // in .env.test.local or environment variables. Gracefully skips when not set.
  // In CI these come from the optional STRIPE_TEST_* repository secrets, which
  // pull requests from forks never receive. playwright.config.ts refuses to
  // start at all with a key that is not a test key.
  // ---------------------------------------------------------------------------
  // @card-23.4
  test("Level 2: real Stripe checkout sandbox redirect and test payment", async ({ page, request }, testInfo) => {
    const stripeKey = process.env.STRIPE_PRIVATE_KEY || process.env.STRIPE_SECRET_KEY || "";
    test.skip(
      !process.env.ENABLE_REAL_STRIPE_TESTS || !/^(sk|rk)_test_/.test(stripeKey),
      "Skipped: Set ENABLE_REAL_STRIPE_TESTS=true with a sk_test_/rk_test_ key in .env.test.local to run real Stripe checkout"
    );
    // A payment round trip through Stripe does not change with the colour
    // scheme or the viewport, and each run is a real sandbox subscription.
    test.skip(testInfo.project.name !== "desktop-light", "Real Stripe checkout runs once, on desktop-light");
    // Two trips to Stripe and a real payment outlast the default 30s.
    test.setTimeout(90_000);

    // Reset database into hosted mode
    await resetDatabase(request, { mode: "hosted" });

    await fastSignIn(page, "Dad");
    await page.goto("/subscription");

    // Click subscribe to launch real Stripe checkout session
    const subscribeAnnual = page.locator('input[value*="Annual"], button:has-text("Annual")').first();
    await subscribeAnnual.click();

    // Verify redirected to Stripe Checkout domain
    await page.waitForURL((url) => url.hostname.includes("stripe.com"), { timeout: 15_000 });
    expect(page.url()).toContain("checkout.stripe.com");

    // Verify Stripe checkout page loaded the plan and price correctly
    await expect(page.locator("body")).toContainText("FamilyPlates Annual Plan");

    // Adaptive Pricing shows the price in the currency of the visitor's IP, and
    // CI runners geolocate abroad (a run was priced in CLP). Switch back to USD
    // so the assertion checks the configured price, not a conversion.
    const chooseCurrency = page.getByRole("group", { name: "Choose currency" });
    if (await chooseCurrency.isVisible()) {
      await chooseCurrency.getByRole("button", { name: /USD/ }).click();
    }
    await expect(page.locator("body")).toContainText("$35.00");

    // Checkout lists its payment methods closed. The Card radio sits under a
    // zero-size accordion button whose cover takes the pointer, so it is
    // checked directly rather than clicked.
    await page.locator("#payment-method-accordion-item-title-card").check({ force: true });

    // These must appear: a Checkout page without them has changed shape, and
    // the test should fail rather than skip the payment it is named for.
    const cardNumber = page.locator("#cardNumber");
    await expect(cardNumber).toBeVisible();
    await cardNumber.fill("4242 4242 4242 4242");
    await page.locator("#cardExpiry").fill("12 / 34");
    await page.locator("#cardCvc").fill("123");
    await page.locator("#billingName").fill("Test Dad");

    // A postal code is asked for only where the billing country uses one, and
    // the country defaults to wherever the runner's IP geolocates.
    const country = page.locator("#billingCountry");
    if (await country.count()) await country.selectOption("US");
    await page.locator("#billingPostalCode").fill("10001");

    // Link is opted in by default and then insists on a phone number.
    const saveWithLink = page.locator("#enableStripePass");
    if ((await saveWithLink.count()) && (await saveWithLink.isChecked())) {
      await saveWithLink.uncheck({ force: true });
    }

    await page.locator("button[type=submit].SubmitButton").click();

    // Back on FamilyPlates, activated by the sync on return rather than by a
    // webhook, which never reaches a CI runner.
    await page.waitForURL((url) => url.hostname === "127.0.0.1" && url.pathname === "/subscription", { timeout: 45_000 });
    await expect(page.locator("body")).toContainText("Thank you for subscribing");
    await expect(page.locator("body")).toContainText("Active Subscription");
  });
});
