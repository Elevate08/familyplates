import { test, expect, Page } from "@playwright/test";
import { resetDatabase, signInAs } from "../support/test-helpers";

// SA-05: the service worker keeps only the grocery list, recipes and meal plan
// (and static assets), and signing out empties the browser's Cache Storage.

// Every kept address, with its query string, so a test can see what is (not) kept.
async function cachedUrls(page: Page): Promise<string[]> {
  return page.evaluate(async () => {
    const urls: string[] = [];
    for (const name of await caches.keys()) {
      const cache = await caches.open(name);
      for (const request of await cache.keys()) {
        const { pathname, search } = new URL(request.url);
        urls.push(pathname + search);
      }
    }
    return urls;
  });
}

async function cachedPaths(page: Page): Promise<string[]> {
  return (await cachedUrls(page)).map((url) => url.split("?")[0]);
}

// The layout registers the worker on load; wait until it controls the page.
async function waitForWorker(page: Page) {
  await page.goto("/grocery_list");
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
}

// Present on the meal plan page (its week picker), and not on the offline notice.
const PLAN_MARKER = '[data-controller="date-picker"]';

// The Planner link points at "/", which redirects to this week's plan. Two copies exist (top bar and
// bottom tab bar); only one is visible at a given width.
function plannerLink(page: Page) {
  return page.locator('a[href="/"]:visible', { hasText: "Planner" }).first();
}

function recipesLink(page: Page) {
  return page.locator('a[href="/recipes"]:visible', { hasText: /Recipe/ }).first();
}

test.describe("Offline pages and sign-out", () => {
  test.beforeEach(async ({ request }) => {
    await resetDatabase(request);
  });

  test("only the offline pages are cached, and signing out clears them", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await waitForWorker(page);

    for (const path of ["/recipes", "/meal_plans", "/preferences/edit", "/admin", "/recipes?q=pasta"]) {
      await page.goto(path);
    }
    await page.goto("/grocery_list");

    // /meal_plans redirects to the current plan, so the plan page itself is what gets kept.
    await expect.poll(() => cachedPaths(page)).toEqual(expect.arrayContaining(["/grocery_list", "/recipes"]));
    const kept = await cachedPaths(page);
    expect(kept.some((path) => /^\/meal_plans\/\d+$/.test(path))).toBe(true);
    for (const path of ["/", "/meal_plans", "/preferences/edit", "/admin"]) expect(kept).not.toContain(path);
    // A search is a page of the recipes area, but one of unboundedly many: only the plain page is kept.
    expect((await cachedUrls(page)).filter((url) => url.includes("?"))).toEqual([]);

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
    const after = await cachedPaths(page);
    for (const path of ["/recipes", "/meal_plans", "/"]) expect(after).not.toContain(path);
  });

  test("the Planner link reaches the plan through a Turbo visit, and then works offline", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await waitForWorker(page);

    // In-app navigation: Turbo fetches "/", follows the redirect to the plan, and swaps the page in.
    await plannerLink(page).click();
    await page.waitForURL(/\/meal_plans\/\d+$/);
    await expect.poll(async () => (await cachedPaths(page)).some((path) => /^\/meal_plans\/\d+$/.test(path))).toBe(true);
    // The plan is kept under its own address only; "/" is not a copy of it.
    expect(await cachedPaths(page)).not.toContain("/");
    const planPath = new URL(page.url()).pathname;

    await recipesLink(page).click();
    await page.waitForURL(/\/recipes$/);
    await expect.poll(() => cachedPaths(page)).toContain("/recipes");

    // Offline, the Planner link and the app's start page both show the plan, not the offline notice.
    await page.context().setOffline(true);
    await plannerLink(page).click();
    await expect(page.locator(PLAN_MARKER)).toBeVisible();
    await expect(page.locator("body")).not.toContainText("You are offline");

    const start = await page.goto("/");
    expect(start?.status()).toBe(200);
    await expect(page.locator(PLAN_MARKER)).toBeVisible();

    // The plan kept from the redirected Turbo visit also opens by its own address, as a navigation.
    const plan = await page.goto(planPath);
    expect(plan?.status()).toBe(200);
    await expect(page.locator(PLAN_MARKER)).toBeVisible();
    await page.context().setOffline(false);
  });

  test("opening the start page by address keeps the plan for offline use", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await waitForWorker(page);

    // A browser navigation: the browser follows the redirect itself, and the plan is kept when its own request arrives.
    await page.goto("/");
    await expect.poll(async () => (await cachedPaths(page)).some((path) => /^\/meal_plans\/\d+$/.test(path))).toBe(true);

    await page.context().setOffline(true);
    for (const path of ["/", "/meal_plans"]) {
      const start = await page.goto(path);
      expect(start?.status()).toBe(200);
      await expect(page.locator(PLAN_MARKER)).toBeVisible();
    }
    await page.context().setOffline(false);
  });

  test("a fresh install saves the grocery list and recipes without a visit", async ({ page }) => {
    await signInAs(page, "Dad", "1234");
    await waitForWorker(page);

    // Start over: no worker, nothing kept, then the page load installs the worker again.
    await page.evaluate(async () => {
      for (const registration of await navigator.serviceWorker.getRegistrations()) await registration.unregister();
      for (const name of await caches.keys()) await caches.delete(name);
    });
    await page.goto("/preferences/edit");
    await page.evaluate(() => navigator.serviceWorker.ready);

    await expect.poll(() => cachedPaths(page)).toEqual(expect.arrayContaining(["/grocery_list", "/recipes"]));
    expect(await cachedPaths(page)).not.toContain("/preferences/edit");

    await page.context().setOffline(true);
    expect((await page.goto("/recipes"))?.status()).toBe(200);
    await page.context().setOffline(false);
  });
});
