import { test, expect } from "@playwright/test";
import { resetDatabase, signInAs } from "./support/test-helpers";

test("Hearth layouts and weekday chips retain shopping behavior", async ({ page, request }, testInfo) => {
  await resetDatabase(request);
  await signInAs(page, "Dad", "1234");
  await page.goto("/preferences");
  await page.locator('input[name="family_member[avatar_color]"][value="#A64730"]').check({ force: true });
  await page.locator("#current_pin").fill("1234");
  await page.getByRole("button", { name: "Save Preferences" }).click();
  await expect(page.getByText("Your preferences were saved successfully!", { exact: false })).toBeVisible();
  for (const [name, path] of [["planner", "/"], ["recipes", "/recipes"], ["groceries", "/grocery_list"], ["preferences", "/preferences"]]) {
    await page.goto(path);
    await expect(page.locator("h1")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
    if (testInfo.project.name === "mobile-light") {
      const tabs = await page.locator(".hearth-nav .fixed.bottom-0").boundingBox();
      expect(tabs).not.toBeNull();
      expect(Math.abs(tabs!.y + tabs!.height - page.viewportSize()!.height)).toBeLessThan(5);
    }
    await page.screenshot({ path: `tmp/hearth-v2-${testInfo.project.name}-${name}.png`, fullPage: true });
  }
  await page.goto("/admin/household/edit");
  const weekdays = page.locator('input[name="household[shopping_wday]"]');
  await expect(weekdays).toHaveCount(7);
  await page.getByRole("radio", { name: "Friday", exact: true }).check({ force: true });
  await page.getByRole("button", { name: "Save Household Settings" }).click();
  await page.goto("/admin/household/edit");
  await expect(page.getByRole("radio", { name: "Friday", exact: true })).toBeChecked();
  await page.getByLabel("How often").selectOption("monthly");
  await expect(weekdays.first()).toBeDisabled();
  await expect(page.locator('select[name="household[shopping_month_day]"]')).toBeEnabled();
  await page.getByLabel("How often").selectOption("fortnightly");
  await expect(weekdays.first()).toBeEnabled();
  await page.screenshot({ path: `tmp/hearth-v2-${testInfo.project.name}-settings.png`, fullPage: true });
});
