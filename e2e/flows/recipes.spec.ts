import { test, expect } from "@playwright/test";
import { resetDatabase, signInAs } from "../support/test-helpers";

test.describe("Interactive Flow: Recipe Management", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("recipe import handles error gracefully with friendly flash", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/recipe_imports/new");

    await page.fill('input[name="url"], input[type="url"]', "https://example.invalid/recipe");
    await page.locator('input[value*="Extract & Import"]').click();

    // Should re-render new with friendly alert in flash-messages, not 500 error
    await expect(page.locator('#flash-messages [role="alert"]').first()).toBeVisible({ timeout: 10_000 });
  });

  test("manual recipe creation and display", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/recipes/new");

    await page.fill('input[name*="[title]"]', "Crispy Homemade Pizza");
    await page.fill('textarea[name*="[instructions]"]', "1. Roll dough.\n2. Add tomato sauce and mozzarella.\n3. Bake at 475F for 12 minutes.");
    await page.locator('input[value*="Save Recipe"]').click();

    // Should redirect to recipe detail
    await page.waitForURL(/\/recipes\/\d+/, { timeout: 10_000 });
    await expect(page.locator("h1")).toContainText("Crispy Homemade Pizza");
  });
});
