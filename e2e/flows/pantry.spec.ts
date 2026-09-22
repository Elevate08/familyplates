import { test, expect } from "@playwright/test";
import { resetDatabase, signInAs } from "../support/test-helpers";

test.describe("Interactive Flow: Pantry & Grocery List", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("add new pantry item, flag it as running low, and verify on grocery list", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await page.goto("/pantry_items");

    // Add item
    await page.fill('#pantry_item_name, input[name="pantry_item[name]"]', "Organic Maple Syrup");
    await page.locator('input[value*="Add Item"]').click();

    // Verify item created
    await expect(page.locator("body")).toContainText("Organic Maple Syrup");

    // Flag item as low stock
    const lowToggle = page.locator('button[aria-label="Mark Organic Maple Syrup as running low"]').first();
    await lowToggle.click();

    // Verify Low stock badge renders
    await expect(page.locator("body")).toContainText("Low");

    // Navigate to grocery list and verify the low stock pantry item appears
    await page.goto("/grocery_list");
    await expect(page.locator("body")).toContainText("Organic Maple Syrup");
  });
});
