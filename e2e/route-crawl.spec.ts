import { test, expect, Page } from "@playwright/test";
import { fastSignIn, resetDatabase, runAxeAudit } from "./support/test-helpers";
import {
  CrawlRecords,
  PARAMETERISED,
  ROLES,
  Role,
  SKIPPED,
  VARIANTS,
  crawlTargets,
  isParameterised,
  loadRoutes,
  routeKey,
  skipReason
} from "./support/route-catalogue";

// Visits every page the app routes, as every kind of visitor, in every project,
// and holds each to the same invariants: no server error, no JavaScript error,
// nothing same-origin that fails to load, no horizontal scroll on a phone, and
// no serious axe violation. The page list comes from config/routes.rb (see
// route-catalogue.ts), so a new page is covered the day it is added.
//
// A redirect is not a failure: a guest sent to the profile picker is the app
// working. The invariants are checked against wherever the visit ends up.

const routes = loadRoutes();
const targets = crawlTargets(routes);

// Console output that is not this application's doing.
const IGNORED_CONSOLE = [/Autofocus processing was blocked/];

// Known axe failures, marked test.fixme on desktop-light (the project axe runs
// in) so the rest of the crawl stays green and gating. The other projects
// still hold these pages to every other invariant. Each entry says what is
// wrong; remove it with the fix.
const HOUSEHOLD = ["member", "admin"] as Role[];
const PLATFORM_ADMIN_PAGES = targets.map((t) => t.key).filter((key) => key.startsWith("GET /platform_admin"));
const KNOWN_AXE_ISSUES = knownIssues(
  [["guest", "platform-admin"], ["GET /signup", "GET /signup/new", "GET /signup/verify"],
    "axe label: avatar colour swatches have no accessible name"],
  [["admin"], ["GET /admin/family_members", "GET /admin/family_members/:id/edit", "GET /onboarding/members"],
    "axe label: avatar colour swatches have no accessible name"],
  [["admin"], ["GET /onboarding/members"], "axe button-name: the icon-only remove-member button has no name"],
  [HOUSEHOLD, ["GET /pantry_items"], "axe button-name: the icon-only remove-item buttons have no name"],
  [["guest", "member", "admin"], PLATFORM_ADMIN_PAGES,
    "axe label: platform-admin sign-in email and password fields have no label"],
  [["platform-admin"], ["GET /platform_admin/session/new"],
    "axe label: platform-admin sign-in email and password fields have no label"],
  [["platform-admin"], ["GET /platform_admin/audit_events", "GET /platform_admin/households", "GET /platform_admin/promotion_programs"],
    "axe label/select-name: platform-admin filter selects and promotion date fields have no label"],
  [HOUSEHOLD, ["GET /recipes/new"], "axe select-name: the ingredient aisle select has no label"],
  [["admin"], ["GET /recipes/:id/edit"], "axe select-name: the ingredient aisle select has no label"],
  [HOUSEHOLD, ["GET /grocery_list", "GET /grocery_list/:meal_plan_id"],
    "axe label: disabled grocery checkboxes have no label"]
);

function knownIssues(...groups: [Role[], string[], string][]): Record<string, string> {
  const issues: Record<string, string> = {};
  for (const [roles, keys, reason] of groups) {
    for (const role of roles) {
      for (const key of keys) {
        const id = `${role} ${key}`;
        issues[id] = issues[id] ? `${issues[id]}; ${reason}` : reason;
      }
    }
  }
  return issues;
}

test.describe("route crawl: every GET route is classified", () => {
  test("each GET route is crawled or skipped with a reason", async ({}, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-light", "The route list is the same in every project");

    const unclassified = routes
      .filter((route) => route.verb === "GET" && isParameterised(route))
      .map(routeKey)
      .filter((key) => !PARAMETERISED[key] && !skipReason(key));

    expect(
      unclassified,
      "These GET routes take parameters the crawl cannot guess. Add each to PARAMETERISED " +
        "with the record to visit it with, or to SKIPPED with the reason it is not a page, " +
        "in e2e/support/route-catalogue.ts"
    ).toEqual([]);

    const known = new Set(routes.map(routeKey));
    const stale = [...Object.keys(PARAMETERISED), ...Object.keys(SKIPPED), ...Object.keys(VARIANTS)].filter(
      (key) => !known.has(key)
    );
    expect(stale, "These catalogue entries name routes that no longer exist").toEqual([]);
  });
});

for (const role of ROLES) {
  test.describe(`route crawl as ${role}`, () => {
    let records: CrawlRecords;

    test.beforeAll(async ({ request }) => {
      await resetDatabase(request);
      const response = await request.post("/__test/crawl_records");
      expect(response.ok()).toBeTruthy();
      records = await response.json();
    });

    for (const target of targets) {
      test(`${role} ${target.key}`, async ({ page, baseURL, isMobile }, testInfo) => {
        const issue = KNOWN_AXE_ISSUES[`${role} ${target.key}`];
        test.fixme(!!issue && testInfo.project.name === "desktop-light", issue);

        await signIn(page, role);
        const problems = watchForProblems(page, baseURL!);

        const path = target.path(records);
        const response = await page.goto(path, { waitUntil: "load" });
        const landedOn = new URL(page.url()).pathname;

        expect(response, `no response for ${path}`).not.toBeNull();
        expect(response!.status(), `${path} ended at ${landedOn} with ${response!.status()}`).toBeLessThan(400);

        problems.push(...(await brokenImages(page, baseURL!)));

        if (isMobile) {
          const overflow = await page.evaluate(
            () => document.documentElement.scrollWidth - window.innerWidth
          );
          expect(overflow, `${landedOn} scrolls ${overflow}px sideways on a phone`).toBeLessThanOrEqual(0);
        }

        expect(problems, `${path} (ended at ${landedOn})`).toEqual([]);

        // axe is the slow part and does not vary with the viewport's colour
        // scheme, so it runs once per page, on desktop-light.
        if (testInfo.project.name === "desktop-light") {
          await runAxeAudit(page, `${role} ${path} (ended at ${landedOn})`);
        }
      });
    }
  });
}

async function signIn(page: Page, role: Role) {
  switch (role) {
    case "guest":
      return;
    case "member":
      return fastSignIn(page, "Mom");
    case "admin":
      return fastSignIn(page, "Dad");
    case "platform-admin": {
      const response = await page.request.post("/__test/sign_in_platform_admin");
      expect(response.ok()).toBeTruthy();
    }
  }
}

// Collects, from the moment it is called, every server error, same-origin
// load failure, uncaught exception and console error on the page.
function watchForProblems(page: Page, baseURL: string): string[] {
  const origin = new URL(baseURL).origin;
  const sameOrigin = (url: string) => url.startsWith(origin);
  const problems: string[] = [];

  page.on("response", (response) => {
    const url = response.url();
    if (!sameOrigin(url)) return;
    const status = response.status();
    const isDocument = response.request().resourceType() === "document";
    if (status >= 500 || (!isDocument && status >= 400)) {
      problems.push(`${status} ${response.request().method()} ${url}`);
    }
  });

  page.on("requestfailed", (request) => {
    // ERR_ABORTED is a request the page itself cancelled - a Turbo prefetch
    // superseded by navigation - not something that failed to load.
    const error = request.failure()?.errorText ?? "";
    if (sameOrigin(request.url()) && !error.includes("ERR_ABORTED")) {
      problems.push(`request failed: ${request.url()} (${error})`);
    }
  });

  page.on("pageerror", (error) => problems.push(`uncaught: ${error.message}`));

  page.on("console", (message) => {
    if (message.type() !== "error") return;
    const text = message.text();
    if (IGNORED_CONSOLE.some((pattern) => pattern.test(text))) return;
    // A third-party image that will not load (recipe photos point at Unsplash)
    // is not this app failing. Same-origin failures are caught above with
    // their status.
    if (text.startsWith("Failed to load resource") && !sameOrigin(message.location().url)) return;
    problems.push(`console: ${text}`);
  });

  return problems;
}

async function brokenImages(page: Page, baseURL: string): Promise<string[]> {
  const origin = new URL(baseURL).origin;
  const broken = await page.evaluate(
    (origin) =>
      Array.from(document.images)
        .filter((img) => img.currentSrc.startsWith(origin) && img.complete && img.naturalWidth === 0)
        .map((img) => img.currentSrc),
    origin
  );
  return broken.map((src) => `broken image: ${src}`);
}
