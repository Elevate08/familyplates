import { test, expect } from "@playwright/test";
import { resetDatabase, preparePageForSnapshot, fastSignIn } from "../support/test-helpers";

test.describe("Stripe & Subscriptions (Hosted Mode)", () => {
  // ---------------------------------------------------------------------------
  // Level 1: In-App Billing UI, Pricing Tiers, and Subscription Lifecycle Flow
  // Runs 100% offline, deterministically, with zero external dependencies.
  // ---------------------------------------------------------------------------
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
  test("Level 2: real Stripe checkout sandbox redirect and test payment", async ({ page, request }) => {
    const stripeKey = process.env.STRIPE_PRIVATE_KEY || process.env.STRIPE_SECRET_KEY || "";
    test.skip(
      !process.env.ENABLE_REAL_STRIPE_TESTS || !/^(sk|rk)_test_/.test(stripeKey),
      "Skipped: Set ENABLE_REAL_STRIPE_TESTS=true with a sk_test_/rk_test_ key in .env.test.local to run real Stripe checkout"
    );

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
    await expect(page.locator("body")).toContainText("$35.00");

    // Fill standard Stripe test credentials if Stripe elements are present
    const emailInput = page.locator('input[type="email"]#email, input[name="email"]').first();
    if (await emailInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      await emailInput.fill("tester@household.test");
    }

    const cardNumberInput = page.locator('input#cardNumber, input[name="cardNumber"]').first();
    if (await cardNumberInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      // Standard Stripe test card
      await cardNumberInput.fill("4242424242424242");
      await page.locator('input#cardExpiry, input[name="cardExpiry"]').fill("12/28");
      await page.locator('input#cardCvc, input[name="cardCvc"]').fill("123");
      await page.locator('input#billingName, input[name="billingName"]').fill("Test Dad");

      // Submit checkout
      await page.locator('button[type="submit"].SubmitButton').click();

      // Verify return redirect to FamilyPlates with activated subscription
      await page.waitForURL((url) => url.pathname.includes("/subscription"), { timeout: 30_000 });
      await expect(page.locator("body")).toContainText("Active Subscription");
    }
  });
});
