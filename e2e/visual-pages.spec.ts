import { test, expect } from "@playwright/test";
import { resetDatabase, preparePageForSnapshot, signInAs } from "./support/test-helpers";

test.describe("Visual Regression: Core Pages", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("profile selection screen", async ({ page }) => {
    await page.goto("/select_profile");
    await preparePageForSnapshot(page);

    await expect(page.locator("h1")).toContainText("Who's in the kitchen today?");
    await expect(page).toHaveScreenshot("profile-selection.png");
  });

  test("weekly meal planner", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/");
    await preparePageForSnapshot(page);

    await expect(page.locator("body")).toBeVisible();
    await expect(page).toHaveScreenshot("weekly-meal-planner.png");
  });

  test("recipes directory", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/recipes");
    await preparePageForSnapshot(page);

    await expect(page.locator("h1")).toContainText("Family Recipe Vault");
    await expect(page).toHaveScreenshot("recipes-directory.png");
  });

  test("pantry management and staples", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/pantry_items");
    await preparePageForSnapshot(page);

    await expect(page.locator("h1")).toContainText("Pantry");
    await expect(page).toHaveScreenshot("pantry-items.png");
  });

  test("aggregated grocery list", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/grocery_list");
    await preparePageForSnapshot(page);

    await expect(page.locator("h1")).toContainText("Grocery List");
    await expect(page).toHaveScreenshot("grocery-list.png");
  });

  test("fridge print view", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/");
    // Click print view link from planner
    const printLink = page.locator('a[href*="/print"]').first();
    if (await printLink.isVisible()) {
      await printLink.click();
    } else {
      await page.goto("/meal_plans/1/print");
    }
    await preparePageForSnapshot(page);

    await expect(page.locator("body")).toBeVisible();
    await expect(page).toHaveScreenshot("fridge-print-view.png");
  });
});
