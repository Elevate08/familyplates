import { execFileSync } from "node:child_process";
import path from "node:path";

// What the route crawl (e2e/support/route-crawl.ts) does with each route the app
// answers. A GET route with no parameters is crawled automatically. Anything
// else must appear below, either with the path to visit or with the reason it
// is not visited. A route in neither list fails the "every GET route is
// crawled or skipped" test, so a new page cannot go unchecked because nobody
// remembered to add it to a list.

export type Route = { verb: string; path: string; controller: string | null; action: string | null };

export type CrawlRecords = {
  household: string;
  recipe: number;
  meal_plan: number;
  family_member: string;
  support_thread: string;
  transfer_token: string;
};

export type Role = "guest" | "member" | "admin" | "platform-admin";

// guest: nobody signed in. member: an ordinary profile (Mom), no PIN.
// admin: the household organizer (Dad), PIN-protected. platform-admin: the
// hosted-platform operator, a separate account with no household profile.
export const ROLES: Role[] = ["guest", "member", "admin", "platform-admin"];

// Parameterised GET routes and the fixture record each one is visited with.
export const PARAMETERISED: Record<string, (r: CrawlRecords) => string> = {
  "GET /support_threads/:id": (r) => `/support_threads/${r.support_thread}`,
  "GET /transfer/:token": (r) => `/transfer/${r.transfer_token}`,
  "GET /admin/family_members/:id/edit": (r) => `/admin/family_members/${r.family_member}/edit`,
  "GET /platform_admin/households/:id": (r) => `/platform_admin/households/${r.household}`,
  "GET /platform_admin/support_threads/:id": (r) => `/platform_admin/support_threads/${r.support_thread}`,
  "GET /recipes/:id": (r) => `/recipes/${r.recipe}`,
  "GET /recipes/:id/edit": (r) => `/recipes/${r.recipe}/edit`,
  "GET /recipes/:id/cook": (r) => `/recipes/${r.recipe}/cook`,
  "GET /meal_plans/:id": (r) => `/meal_plans/${r.meal_plan}`,
  "GET /meal_plans/:id/print": (r) => `/meal_plans/${r.meal_plan}/print`,
  "GET /grocery_list/:meal_plan_id": (r) => `/grocery_list/${r.meal_plan}`
};

// Query strings that switch a route to a different template, crawled as pages
// of their own.
export const VARIANTS: Record<string, string[]> = {
  "GET /": ["view=month"],
  "GET /meal_plans/:id": ["view=month"],
  "GET /meal_plans/:id/print": ["view=month"]
};

// Routes the crawl deliberately does not visit, and why. Say what covers the
// route instead where something does.
export const SKIPPED: Record<string, string> = {
  "GET /up": "Load-balancer health check. Plain text, not a page.",
  "GET /manifest": "PWA manifest JSON, not a page (pwa_controller_test).",
  "GET /service-worker": "Service worker JavaScript, not a page (pwa_controller_test).",
  "GET /account_data/export": "Sends a JSON attachment the browser downloads instead of rendering (account_data_controller_test).",
  "GET /calendars/feed/:token": "iCalendar feed for calendar apps, not a page (calendar_feeds_controller_test).",
  "GET /calendars/feed/:token/members/:member_id": "iCalendar feed for calendar apps, not a page (calendar_feeds_controller_test).",
  "GET /auth/:provider/callback": "OAuth return leg. Only meaningful with a provider's state and code (external_auth_controller_test).",
  "GET /meal_plans/new": "Routed by `resources :meal_plans` with no action behind it, so it 404s (PageCatalogue::UNIMPLEMENTED).",
  "GET /meal_plans/:id/edit": "Routed by `resources :meal_plans` with no action behind it, so it 404s (PageCatalogue::UNIMPLEMENTED).",
  "GET /pay/payments/:id": "Pay engine's 3-D Secure confirmation page. Needs a real Stripe PaymentIntent.",
  "GET /recede_historical_location": "turbo-rails bridge for a native app shell. No FamilyPlates UI.",
  "GET /resume_historical_location": "turbo-rails bridge for a native app shell. No FamilyPlates UI.",
  "GET /refresh_historical_location": "turbo-rails bridge for a native app shell. No FamilyPlates UI."
};

// Whole families of framework routes, matched by prefix.
export const SKIPPED_PREFIXES: [string, string][] = [
  ["GET /rails/active_storage/", "Serves uploaded files by signed id. The crawl checks images through the pages that show them."],
  ["GET /rails/conductor/", "Action Mailbox's development-only conductor. Refuses every request outside development."],
  ["GET /rails/action_mailbox/", "Inbound-email webhook endpoints for mail providers, not pages."],
  ["GET /__test/", "Test-only helpers the suite itself calls."]
];

export function skipReason(key: string): string | undefined {
  return SKIPPED[key] ?? SKIPPED_PREFIXES.find(([prefix]) => key.startsWith(prefix))?.[1];
}

// Asked of Rails directly (test/support/route_inventory.rb), not of the running
// server, because Playwright lists the tests before it starts the web server.
// Workers inherit the environment of the process that lists them, so the
// ~2s boot happens once per run, not once per worker.
export function loadRoutes(): Route[] {
  if (!process.env.E2E_ROUTE_INVENTORY) {
    const root = path.resolve(__dirname, "../..");
    process.env.E2E_ROUTE_INVENTORY = execFileSync(
      "bin/rails",
      ["runner", 'require "./test/support/route_inventory"; puts RouteInventory.all.map(&:to_h).to_json'],
      { cwd: root, env: { ...process.env, RAILS_ENV: "test" }, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }
    ).trim();
  }
  return JSON.parse(process.env.E2E_ROUTE_INVENTORY);
}

export function routeKey(route: Route): string {
  return `${route.verb} ${route.path}`;
}

export function isParameterised(route: Route): boolean {
  return /[:*]/.test(route.path);
}

export type CrawlTarget = { key: string; path: (r: CrawlRecords) => string };

// Every page the crawl visits, in route order, variants after their route.
export function crawlTargets(routes: Route[]): CrawlTarget[] {
  const targets: CrawlTarget[] = [];
  for (const route of routes.filter((r) => r.verb === "GET")) {
    const key = routeKey(route);
    if (skipReason(key)) continue;

    if (PARAMETERISED[key]) {
      targets.push({ key, path: PARAMETERISED[key] });
    } else if (!isParameterised(route)) {
      targets.push({ key, path: () => route.path });
    } else {
      continue; // unclassified - reported by the coverage test
    }

    const base = targets[targets.length - 1].path;
    for (const query of VARIANTS[key] ?? []) {
      targets.push({ key: `${key}?${query}`, path: (r) => `${base(r)}?${query}` });
    }
  }
  return targets;
}
