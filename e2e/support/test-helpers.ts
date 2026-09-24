import { Page, APIRequestContext, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

export const FROZEN_TEST_TIME = "2026-09-22T12:00:00.000Z";

/**
 * Resets the SQLite test database back to pristine test fixtures, with the
 * server clock frozen at FROZEN_TEST_TIME so fixture dates and rendered pages
 * match the frozen browser clock whatever day the suite runs on.
 */
export async function resetDatabase(request: APIRequestContext, { mode = "appliance" } = {}) {
  const response = await request.post("/__test/reset", { data: { mode, now: FROZEN_TEST_TIME } });
  expect(response.ok()).toBeTruthy();
}

/**
 * Ensures zero-animation and frozen clock state for consistent snapshots.
 */
export async function preparePageForSnapshot(page: Page) {
  // 1. Freeze clock to avoid day-of-week and time-of-day visual drift
  await page.clock.setFixedTime(new Date(FROZEN_TEST_TIME));

  // 2. Inject CSS disabling all animations, transitions, and blurs
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
      }
    `
  });

  // 3. Ensure all fonts and DOM assets are fully painted
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState("domcontentloaded");

  // 4. Wait for every image. Recipe cards lazy-load a remote photo, and a
  //    screenshot taken before it arrives shows a blank card (a CI run
  //    differed on 24% of the recipes page that way). Loading them eagerly
  //    also covers cards below the fold of a full-page shot.
  await page.evaluate(async () => {
    await Promise.all(
      Array.from(document.images).map((img) => {
        img.loading = "eager";
        if (img.complete) return;
        return new Promise((resolve) => {
          img.addEventListener("load", resolve, { once: true });
          img.addEventListener("error", resolve, { once: true });
        });
      })
    );
  });
}

/**
 * Signs in as a family member through the real UI flow.
 */
export async function signInAs(page: Page, memberName = "Dad", pin = "1234") {
  await page.goto("/select_profile");
  await page.waitForLoadState("domcontentloaded");

  // Click the profile button
  const profileButton = page.locator(`button:has-text("${memberName}"), form button:has-text("${memberName}")`).first();
  await profileButton.click();

  // If PIN modal opens, fill and submit
  const pinInput = page.locator("#pin-input");
  if (await pinInput.isVisible({ timeout: 1500 }).catch(() => false)) {
    await pinInput.fill(pin);
    await page.locator("#select-pin-submit").click();
  }

  // Verify redirected away from select_profile
  await page.waitForURL((url) => !url.pathname.includes("/select_profile"), { timeout: 10_000 });
}

/**
 * Fast API sign-in setting session cookies directly, ideal for hosted-mode tests.
 */
export async function fastSignIn(page: Page, memberName = "Dad") {
  const response = await page.request.post("/__test/sign_in", { data: { name: memberName } });
  expect(response.ok()).toBeTruthy();
}

/**
 * Runs an accessibility audit with Axe-core, asserting no critical or serious issues.
 */
export async function runAxeAudit(page: Page, contextName: string, { checkContrast = false } = {}) {
  const builder = new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]);

  if (!checkContrast) {
    builder.disableRules(["color-contrast"]);
  }

  const accessibilityScanResults = await builder.analyze();

  const severeViolations = accessibilityScanResults.violations.filter(
    (v) => v.impact === "critical" || v.impact === "serious"
  );

  expect(
    severeViolations,
    `Accessibility violations found in ${contextName}:\n${JSON.stringify(severeViolations, null, 2)}`
  ).toEqual([]);
}
