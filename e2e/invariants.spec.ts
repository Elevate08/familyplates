import { test, expect } from "@playwright/test";
import { resetDatabase, signInAs, runAxeAudit } from "./support/test-helpers";

test.describe("Layout Invariants & Accessibility", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("pages have zero horizontal scroll on mobile viewports", async ({ page, isMobile }) => {
    test.skip(!isMobile, "Horizontal overflow check applies to mobile viewports");

    await signInAs(page, "Dad", "1234");

    const paths = ["/", "/recipes", "/pantry_items", "/grocery_list"];
    for (const path of paths) {
      await page.goto(path);
      await page.waitForLoadState("domcontentloaded");

      const hasHorizontalOverflow = await page.evaluate(() => {
        return document.documentElement.scrollWidth > window.innerWidth;
      });

      expect(hasHorizontalOverflow, `Page ${path} overflows horizontally on mobile`).toBeFalsy();
    }
  });

  test("core pages pass WCAG 2.1 AA accessibility audits", async ({ page }, testInfo) => {
    // Only run on desktop-light to avoid redundant runs across all browser projects
    test.skip(testInfo.project.name !== "desktop-light", "Run a11y audit once per platform");

    await page.goto("/select_profile");
    await runAxeAudit(page, "Profile Selection Page");

    await signInAs(page, "Dad", "1234");

    await page.goto("/");
    await runAxeAudit(page, "Weekly Meal Planner");

    await page.goto("/recipes");
    await runAxeAudit(page, "Recipe Index");
  });
});
