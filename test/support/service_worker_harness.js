// Runs the rendered service worker (stdin) against fake caches and a fake
// network, then prints what it did as JSON. Used by PwaControllerTest;
// nothing here ships to the browser.
const vm = require("vm");
const fs = require("fs");

const source = fs.readFileSync(0, "utf8");
const ORIGIN = "http://localhost";

// A page request. `mode: "navigate"` is a browser navigation (redirects are left to the browser);
// `mode: "cors"` with an HTML Accept header is a Turbo visit or frame fetch.
function fakeRequest(path, { accept = "text/html", mode = "navigate", method = "GET", origin = ORIGIN, headers = {} } = {}) {
  const extra = Object.fromEntries(Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value]));
  return {
    method,
    url: origin + path,
    mode,
    redirect: mode === "navigate" ? "manual" : "follow",
    headers: { get: (name) => (name.toLowerCase() === "accept" ? accept : extra[name.toLowerCase()] ?? null) }
  };
}

function fakeResponse(body, { url, redirected = false, type = "basic", status = 200 } = {}) {
  const response = new Response(status === 0 ? null : body, { status: status === 0 ? 200 : status });
  Object.defineProperty(response, "url", { value: url });
  Object.defineProperty(response, "redirected", { value: redirected });
  Object.defineProperty(response, "type", { value: type });
  if (status === 0) Object.defineProperty(response, "status", { value: 0 });
  return response;
}

// The fake network answers "network <final path>". `redirects` maps a path to where the server sends it;
// `statuses` maps a path to a status other than 200. A request that leaves redirects to the browser
// (navigate mode) gets an opaque redirect, as in Chromium. `calls` records every request made.
function fakeNetwork(redirects = {}, statuses = {}) {
  const calls = [];
  return {
    calls,
    fetch: async (req) => {
      const manual = typeof req !== "string" && req.redirect === "manual";
      const asked = new URL(typeof req === "string" ? req : req.url, ORIGIN);
      calls.push(asked.pathname + asked.search);
      const target = redirects[asked.pathname];
      if (target && manual) return fakeResponse("", { url: "", type: "opaqueredirect", status: 0 });
      const final = target ? new URL(target + asked.search, ORIGIN) : asked;
      return fakeResponse("network " + final.pathname + final.search, {
        url: final.href, redirected: Boolean(target), status: statuses[final.pathname] || 200
      });
    }
  };
}

const offlineNetwork = { fetch: async () => { throw new TypeError("offline"); } };

function boot(network) {
  const stores = new Map();
  const puts = [];
  const deletes = [];
  let clock = 0;
  const keyOf = (req) => (typeof req === "string" ? new URL(req, ORIGIN).href : req.url);
  const open = async (name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    return {
      put: async (req, res) => { puts.push(new URL(keyOf(req)).pathname); store.set(keyOf(req), res); },
      addAll: async (urls) => { for (const url of urls) store.set(keyOf(url), new Response("precached " + url)); },
      keys: async () => [...store.keys()].map((url) => ({ url })),
      match: async (req) => (store.has(keyOf(req)) ? store.get(keyOf(req)).clone() : undefined),
      delete: async (req) => { deletes.push(new URL(keyOf(req)).pathname); return store.delete(keyOf(req)); }
    };
  };
  const caches = {
    open,
    keys: async () => [...stores.keys()],
    delete: async (name) => stores.delete(name),
    match: async (req) => {
      for (const store of stores.values()) if (store.has(keyOf(req))) return store.get(keyOf(req)).clone();
      return undefined;
    }
  };
  const listeners = {};
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (type, fn) => { listeners[type] = fn; },
    skipWaiting: () => Promise.resolve(),
    clients: { claim: () => Promise.resolve() }
  };
  const worker = { listeners, caches, puts, deletes, stores, network };
  // Date.now() ticks once per call, so "most recent" is unambiguous
  const context = {
    self, caches, URL, Response, Headers, TypeError, Date: { now: () => ++clock }, console: { warn() {}, log() {} },
    fetch: (req) => worker.network.fetch(req)
  };
  vm.runInNewContext(source, context);
  return worker;
}

// Sends one request through the worker. `error` is set when the worker answered with a network error.
async function dispatch(worker, request) {
  let responded;
  const lifetime = [];
  const event = { request, respondWith: (promise) => { responded = promise; }, waitUntil: (promise) => { lifetime.push(promise); } };
  worker.listeners.fetch(event);
  let response = null;
  let error = null;
  if (responded) {
    try { response = await responded; } catch (e) { error = String(e); }
  }
  await Promise.all(lifetime);
  await new Promise((resolve) => setTimeout(resolve, 0));
  return { intercepted: responded !== undefined, response, error };
}

async function install(worker) {
  let installing;
  worker.listeners.install({ waitUntil: (p) => { installing = p; } });
  await installing;
}

const text = async (r) => (r.response ? r.response.text() : null);
const goOffline = (worker) => { worker.network = offlineNetwork; };
const uniqueSorted = (list) => [...new Set(list)].sort();
const keptPaths = (worker) => [...worker.stores.values()].flatMap((store) => [...store.keys()].map((key) => new URL(key).pathname)).sort();

async function run() {
  const results = {};
  const online = fakeNetwork();

  // Online: which GETs end up in the cache?
  const worker = boot(online);
  const probes = {
    html: [
      "/", "/grocery_list", "/grocery_list/3", "/grocery_list/current", "/recipes", "/recipes/12", "/recipes/12/cook",
      "/meal_plans", "/meal_plans/4", "/meal_plans/4/print", "/recipes/new", "/recipes/12/edit", "/meal_plans/new",
      "/meal_plans/4/edit", "/platform_admin", "/platform_admin/households", "/account_data", "/subscription",
      "/support/threads", "/preferences/edit", "/session/new", "/devices", "/pair", "/admin", "/activity", "/pantry_items"
    ],
    other: ["/account_data/export", "/calendars/feed/abc", "/up"],
    assets: ["/assets/application-abc123.css", "/icon.png", "/icon.svg", "/favicon.ico", "/manifest.json"]
  };
  for (const path of probes.html) await dispatch(worker, fakeRequest(path));
  for (const path of probes.other) await dispatch(worker, fakeRequest(path, { accept: "*/*", mode: "cors" }));
  for (const path of probes.assets) await dispatch(worker, fakeRequest(path, { accept: "*/*", mode: "no-cors" }));
  results.cachedPaths = uniqueSorted(worker.puts);

  // Other GET page that asks for HTML but is the export link, and non-GET and cross-origin.
  results.postIntercepted = (await dispatch(worker, fakeRequest("/recipes", { method: "POST" }))).intercepted;
  results.crossOriginIntercepted = (await dispatch(worker, fakeRequest("/recipes", { origin: "https://cdn.example.com" }))).intercepted;
  results.exportIntercepted = (await dispatch(worker, fakeRequest("/account_data/export", { accept: "*/*", mode: "cors" }))).intercepted;

  // A redirect to another page (for example /grocery_list bounced to sign-in) is never kept.
  const bounced = boot(fakeNetwork({ "/grocery_list": "/session/new", "/recipes": "/session/new", "/": "/session/new" }));
  await dispatch(bounced, fakeRequest("/grocery_list", { mode: "cors" }));
  await dispatch(bounced, fakeRequest("/recipes", { mode: "cors" }));
  await dispatch(bounced, fakeRequest("/", { mode: "cors" }));
  await dispatch(bounced, fakeRequest("/", { mode: "navigate" }));
  results.signInRedirectCached = bounced.puts;

  // A Turbo visit to "/" or "/meal_plans" follows the redirect: the plan is kept under its own address,
  // stamped with the time it was kept, and nothing else is written or fetched.
  const plan = { "/": "/meal_plans/4", "/meal_plans": "/meal_plans/4" };
  const turbo = boot(fakeNetwork(plan));
  await dispatch(turbo, fakeRequest("/", { mode: "cors" }));
  results.turboHomeCached = keptPaths(turbo);
  results.turboNetworkCalls = [...turbo.network.calls];
  const stamped = [...turbo.stores.values()][0].get(ORIGIN + "/meal_plans/4");
  results.turboStamp = stamped.headers.get("X-SW-Cached-At");
  const turboIndex = boot(fakeNetwork(plan));
  await dispatch(turboIndex, fakeRequest("/meal_plans", { mode: "cors" }));
  results.turboIndexCached = keptPaths(turboIndex);

  // A browser navigation leaves the redirect to the browser: the worker keeps nothing and makes no second
  // request; the plan is kept when the browser's own request for it comes through.
  const navigated = boot(fakeNetwork(plan));
  const opaque = await dispatch(navigated, fakeRequest("/", { mode: "navigate" }));
  await dispatch(navigated, fakeRequest("/meal_plans", { mode: "navigate" }));
  results.navigateRedirectStatus = opaque.response.status;
  results.navigateRedirectCached = keptPaths(navigated);
  results.navigateRedirectCalls = [...navigated.network.calls];
  await dispatch(navigated, fakeRequest("/meal_plans/4", { mode: "navigate" }));
  results.navigateFollowedCached = keptPaths(navigated);

  // Offline, "/" and "/meal_plans" show the most recently kept plan without a query string.
  const plans = boot(fakeNetwork());
  await dispatch(plans, fakeRequest("/meal_plans/9", { mode: "cors" }));
  await dispatch(plans, fakeRequest("/meal_plans/4", { mode: "navigate" }));
  await dispatch(plans, fakeRequest("/meal_plans/9?view=month", { mode: "cors" }));
  await dispatch(plans, fakeRequest("/recipes/12", { mode: "navigate" }));
  goOffline(plans);
  results.latestPlanHome = await text(await dispatch(plans, fakeRequest("/")));
  results.latestPlanIndex = await text(await dispatch(plans, fakeRequest("/meal_plans")));
  results.latestPlanQuery = await text(await dispatch(plans, fakeRequest("/meal_plans?view=month")));
  plans.network = fakeNetwork();
  await dispatch(plans, fakeRequest("/meal_plans/9", { mode: "navigate" }));
  goOffline(plans);
  results.latestPlanAfterRevisit = await text(await dispatch(plans, fakeRequest("/")));
  results.latestPlanTurbo = await dispatch(plans, fakeRequest("/", { mode: "cors" }));

  // With no plan kept, "/" gets the notice rather than another page.
  const noPlan = boot(fakeNetwork());
  await dispatch(noPlan, fakeRequest("/recipes/12", { mode: "navigate" }));
  goOffline(noPlan);
  const noPlanHome = await dispatch(noPlan, fakeRequest("/"));
  results.noPlanHome = { body: await text(noPlanHome), status: noPlanHome.response && noPlanHome.response.status };

  // Turbo Frame responses are fragments: never kept, and never over the full page.
  const frames = boot(online);
  await dispatch(frames, fakeRequest("/recipes/12", { mode: "navigate" }));
  const framesMark = frames.puts.length;
  const frame = await dispatch(frames, fakeRequest("/recipes/12", { mode: "cors", headers: { "Turbo-Frame": "recipe_card" } }));
  await dispatch(frames, fakeRequest("/recipes", { mode: "cors", headers: { "Turbo-Frame": "list" } }));
  results.frameWrites = frames.puts.slice(framesMark);
  results.frameBody = await text(frame);

  // A query string (search, tag filter, view variant) is a different page of the same area: not kept.
  const queries = boot(online);
  for (const path of ["/recipes?q=pasta", "/recipes?tag=dinner&page=2", "/grocery_list?view=aisle", "/meal_plans/4?view=month", "/recipes/12?servings=4"]) {
    await dispatch(queries, fakeRequest(path, { mode: "cors" }));
    await dispatch(queries, fakeRequest(path, { mode: "navigate" }));
  }
  results.queryWrites = queries.puts;

  // Uploaded recipe photos are kept like assets (stale-while-revalidate); the disk endpoint behind them is not.
  const photos = boot(online);
  const blob = "/rails/active_storage/blobs/redirect/abc/photo.jpg";
  const variant = "/rails/active_storage/representations/redirect/abc/def/photo.jpg";
  const proxied = "/rails/active_storage/blobs/proxy/abc/photo.jpg";
  for (const path of [blob, variant, proxied, "/rails/active_storage/disk/key/photo.jpg"]) {
    await dispatch(photos, fakeRequest(path, { accept: "image/*", mode: "no-cors" }));
  }
  results.photoCached = uniqueSorted(photos.puts);
  goOffline(photos);
  results.photoOffline = await text(await dispatch(photos, fakeRequest(blob, { accept: "image/*", mode: "no-cors" })));
  results.photoNeverSeenOffline = (await dispatch(photos, fakeRequest("/rails/active_storage/blobs/redirect/zzz/other.jpg", { accept: "image/*", mode: "no-cors" }))).error;

  // A page or photo the server reports gone (404, 410) loses its kept copy.
  const gone = boot(online);
  await dispatch(gone, fakeRequest("/recipes/12", { mode: "navigate" }));
  await dispatch(gone, fakeRequest("/recipes/13", { mode: "navigate" }));
  await dispatch(gone, fakeRequest(blob, { accept: "image/*", mode: "no-cors" }));
  await dispatch(gone, fakeRequest("/assets/application-abc123.css", { accept: "text/css", mode: "no-cors" }));
  gone.network = fakeNetwork({}, { "/recipes/12": 404, "/recipes/13": 500, [blob]: 410, "/assets/application-abc123.css": 404 });
  const goneReply = await dispatch(gone, fakeRequest("/recipes/12", { mode: "navigate" }));
  await dispatch(gone, fakeRequest("/recipes/13", { mode: "navigate" }));
  await dispatch(gone, fakeRequest(blob, { accept: "image/*", mode: "no-cors" }));
  await dispatch(gone, fakeRequest("/assets/application-abc123.css", { accept: "text/css", mode: "no-cors" }));
  results.goneStatus = goneReply.response.status;
  results.goneKept = keptPaths(gone);

  // Install saves the grocery list and recipes when signed in, and nothing when the answer is a redirect.
  const signedIn = boot(fakeNetwork());
  await install(signedIn);
  results.installSignedIn = keptPaths(signedIn);
  const signedOut = boot(fakeNetwork({ "/grocery_list": "/session/new", "/recipes": "/session/new" }));
  await install(signedOut);
  results.installSignedOut = keptPaths(signedOut);
  const failing = boot(fakeNetwork({}, { "/grocery_list": 503, "/recipes": 404 }));
  await install(failing);
  results.installFailing = keptPaths(failing);

  // Offline: an allowed page that was viewed comes back from the cache.
  const later = boot(fakeNetwork(plan));
  await dispatch(later, fakeRequest("/", { mode: "cors" }));
  await dispatch(later, fakeRequest("/recipes/12"));
  goOffline(later);
  results.offlineCachedRecipe = await text(await dispatch(later, fakeRequest("/recipes/12")));
  results.offlineHome = await text(await dispatch(later, fakeRequest("/")));
  results.offlinePlanIndex = await text(await dispatch(later, fakeRequest("/meal_plans")));
  results.offlinePlan = await text(await dispatch(later, fakeRequest("/meal_plans/4")));
  const refused = {};
  for (const path of ["/platform_admin", "/account_data", "/subscription", "/recipes/99", "/grocery_list"]) {
    const reply = await dispatch(later, fakeRequest(path));
    refused[path] = { body: await text(reply), status: reply.response && reply.response.status };
  }
  results.offlineFallbacks = refused;

  // Only a navigation gets the notice page or the plan; a Turbo or script fetch gets the network error.
  const empty = boot(online);
  goOffline(empty);
  const scripted = {};
  for (const path of ["/recipes/99", "/account_data", "/"]) {
    const reply = await dispatch(empty, fakeRequest(path, { mode: "cors" }));
    scripted[path] = { error: reply.error, intercepted: reply.intercepted, response: reply.response === null };
  }
  results.offlineNonNavigation = scripted;

  // Activate deletes older cache versions and keeps its own.
  const upgraded = boot(online);
  for (const old of ["familyplates-v1", "familyplates-v2", "familyplates-v3", "familyplates-v4"]) await upgraded.caches.open(old);
  await install(upgraded);
  let activation;
  upgraded.listeners.activate({ waitUntil: (p) => { activation = p; } });
  await activation;
  results.cachesAfterActivate = await upgraded.caches.keys();

  console.log(JSON.stringify(results));
}

run().catch((error) => { console.error(error); process.exit(1); });
