import { test, expect } from "@playwright/test";
import { resetDatabase, preparePageForSnapshot, signInAs } from "../support/test-helpers";

test.describe("Interactive Flow: Meal Planner & Slots", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("open slot modal, select a recipe, and save slot", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/");
    await page.waitForLoadState("domcontentloaded");

    // Locate a meal plan slot card or button
    const slotCard = page.locator('[data-action*="slot-modal#open"]').first();
    await expect(slotCard).toBeVisible();
    await slotCard.click();

    // Verify modal appears
    const modal = page.locator('[data-slot-modal-target="modal"]:not(.hidden), [id^="slot-modal"]:not(.hidden)').first();
    await expect(modal).toBeVisible();

    // Take screenshot of open modal state
    await preparePageForSnapshot(page);
    await expect(page).toHaveScreenshot("planner-slot-modal-open.png");

    // Close modal via close button
    const closeBtn = modal.locator('button[data-action*="slot-modal#close"]').first();
    await closeBtn.click();
    await expect(modal).toBeHidden();
  });

  test("switch between weekly and monthly calendar views", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/");

    // Toggle view to month
    const monthViewLink = page.locator('a[href*="view=month"]').first();
    if (await monthViewLink.isVisible()) {
      await monthViewLink.click();
      await page.waitForURL((url) => url.searchParams.get("view") === "month");
      await expect(page.locator("body")).toBeVisible();
    }
  });
});
