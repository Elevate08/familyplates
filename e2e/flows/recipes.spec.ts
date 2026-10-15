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

    // The fetch runs in a background job behind a waiting page that reloads itself
    // (every 3 seconds) until the job has failed, then sends the person back to the
    // form with the reason. The server runs the job itself (E2E_RUN_JOBS).
    await page.waitForURL(/\/recipe_imports\/new$/, { timeout: 15_000 });

    // A friendly alert in flash-messages, not a 500 error
    const alert = page.locator('#flash-messages [role="alert"]').first();
    await expect(alert).toBeVisible();
    await expect(alert).toContainText("Could not fetch recipe from that web address");
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
