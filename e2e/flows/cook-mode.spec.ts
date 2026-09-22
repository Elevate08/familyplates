import { test, expect } from "@playwright/test";
import { resetDatabase, preparePageForSnapshot, signInAs } from "../support/test-helpers";

test.describe("Interactive Flow: Cook Mode", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("full-screen step navigation and ingredient drawer", async ({ page }) => {
    await signInAs(page, "Dad", "1234");

    // Navigate to recipes, pick first recipe, and launch Cook Mode
    await page.goto("/recipes");
    await page.locator('a[aria-label^="View "]').first().click();
    await page.waitForLoadState("domcontentloaded");

    const cookButton = page.locator("a[href*='/cook']").first();
    await cookButton.click();
    await page.waitForLoadState("domcontentloaded");

    // Verify cook mode header & initial step
    const counter = page.locator('[data-cook-mode-target="counter"]');
    await expect(counter).toBeVisible();

    const nextButton = page.locator('[data-cook-mode-target="nextButton"]');
    const prevButton = page.locator('[data-cook-mode-target="previousButton"]');

    // If recipe has multiple steps, test advancing. If 1 step, finish button is shown.
    if (await nextButton.isVisible()) {
      await nextButton.click();
      await expect(prevButton).toBeEnabled();
      await prevButton.click();
    } else {
      await expect(page.locator('[data-cook-mode-target="finishLink"]')).toBeVisible();
    }

    // Test toggling ingredients drawer if recipe has ingredients
    const drawerButton = page.locator('button[data-action*="cook-mode#toggleDrawer"]');
    if (await drawerButton.isVisible()) {
      await drawerButton.click();
      const drawer = page.locator("#cook-mode-drawer, [data-cook-mode-target='drawer']").first();
      await expect(drawer).toBeVisible();
    }

    await preparePageForSnapshot(page);
    await expect(page).toHaveScreenshot("cook-mode-active.png");
  });
});
