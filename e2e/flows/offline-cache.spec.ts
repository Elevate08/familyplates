import { test, expect, Page } from "@playwright/test";
import { resetDatabase, signInAs } from "../support/test-helpers";

// SA-05: the service worker keeps only the grocery list, recipes and meal plan
// (and static assets), and signing out empties the browser's Cache Storage.

async function cachedPaths(page: Page): Promise<string[]> {
  return page.evaluate(async () => {
    const paths: string[] = [];
    for (const name of await caches.keys()) {
      const cache = await caches.open(name);
      for (const request of await cache.keys()) paths.push(new URL(request.url).pathname);
    }
    return paths;
  });
}

test.describe("Offline pages and sign-out", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("only the offline pages are cached, and signing out clears them", async ({ page }) => {
    await signInAs(page, "Dad", "1234");

    // The layout registers the worker on load; wait until it controls the page.
    await page.goto("/grocery_list");
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.reload();
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);

    for (const path of ["/recipes", "/meal_plans", "/preferences/edit", "/admin"]) {
      await page.goto(path);
    }
    await page.goto("/grocery_list");

    // /meal_plans redirects to the current plan, so the plan page itself is what gets kept.
    await expect.poll(() => cachedPaths(page)).toEqual(expect.arrayContaining(["/grocery_list", "/recipes", "/meal_plans"]));
    const kept = await cachedPaths(page);
    expect(kept.some((path) => /^\/meal_plans\/\d+$/.test(path))).toBe(true);
    for (const path of ["/preferences/edit", "/admin"]) expect(kept).not.toContain(path);

    // Offline, a page outside the three areas gets the offline notice, not another page.
    await page.context().setOffline(true);
    expect((await page.goto("/meal_plans"))?.status()).toBe(200);
    const response = await page.goto("/preferences/edit");
    expect(response?.status()).toBe(503);
    await expect(page.locator("body")).toContainText("Only these pages work without a connection");
    await expect(page.locator("body")).toContainText("Grocery list");
    await page.context().setOffline(false);

    // Sign out through the profile menu.
    await page.goto("/grocery_list");
    await page.locator('button[title="Active Profile & Kitchen Settings"]').dispatchEvent("click");
    // dispatchEvent: on a phone the bottom navigation overlaps the menu
    await page.getByRole("button", { name: "Sign Out" }).dispatchEvent("click");
    await page.waitForURL(/\/select_profile/);

    // Clear-Site-Data wipes Cache Storage (the worker re-registers on this page and starts empty).
    await expect.poll(() => cachedPaths(page)).not.toContain("/grocery_list");
    expect(await cachedPaths(page)).not.toContain("/recipes");
  });
});
