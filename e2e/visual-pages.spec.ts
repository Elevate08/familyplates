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
    // The planner opens the fridge sheet in a new tab. Register before the
    // click so even a fast popup is captured, then prepare that document.
    const printPagePromise = page.waitForEvent("popup");
    await page.getByRole("link", { name: "Print Week Schedule", exact: true }).click();
    const printPage = await printPagePromise;
    await printPage.waitForLoadState("domcontentloaded");
    await expect(printPage).toHaveURL(/\/meal_plans\/\d+\/print\?/);
    await preparePageForSnapshot(printPage);

    await expect(printPage.getByRole("heading", { name: "Fridge Print Preview (Weekly Landscape Table)", exact: true })).toBeVisible();
    await expect(printPage).toHaveScreenshot("fridge-print-view.png");
  });
});
