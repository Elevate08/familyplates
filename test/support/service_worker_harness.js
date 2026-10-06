// Runs the rendered service worker (stdin) against fake caches and a fake
// network, then prints what it did as JSON. Used by ServiceWorkerBehaviourTest;
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

// The fake network answers "network <final path>". `redirects` maps a path to where the server sends it.
// A request that leaves redirects to the browser (navigate mode) gets an opaque redirect, as in Chromium.
function fakeNetwork(redirects = {}) {
  const calls = [];
  const network = {
    calls,
    fetch: async (req) => {
      const manual = typeof req !== "string" && req.redirect === "manual";
      const asked = new URL(typeof req === "string" ? req : req.url, ORIGIN);
      calls.push(asked.pathname + asked.search);
      const target = redirects[asked.pathname];
      if (target && manual) return fakeResponse("", { url: "", type: "opaqueredirect", status: 0 });
      const final = target ? new URL(target + asked.search, ORIGIN) : asked;
      return fakeResponse("network " + final.pathname + final.search, { url: final.href, redirected: Boolean(target) });
    }
  };
  return network;
}

const offlineNetwork = { fetch: async () => { throw new TypeError("offline"); } };

function boot(network) {
  const stores = new Map();
  const puts = [];
  const keyOf = (req) => (typeof req === "string" ? new URL(req, ORIGIN).href : req.url);
  const open = async (name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    return {
      put: async (req, res) => { puts.push(new URL(keyOf(req)).pathname); store.set(keyOf(req), res); },
      addAll: async (urls) => { for (const url of urls) store.set(keyOf(url), new Response("precached " + url)); }
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
  const worker = { listeners, caches, puts, stores, network };
  const context = { self, caches, URL, Response, TypeError, console: { warn() {}, log() {} }, fetch: (req) => worker.network.fetch(req) };
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

const text = async (r) => (r.response ? r.response.text() : null);
const goOffline = (worker) => { worker.network = offlineNetwork; };
const putsSince = (worker, from) => worker.puts.slice(from);

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
  results.cachedPaths = [...new Set(worker.puts)].sort();

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

  // Turbo visits to "/" and "/meal_plans" reach the plan through a redirect: the plan is kept under its own
  // address, and as the "/" and "/meal_plans" copies.
  const plan = { "/": "/meal_plans/4", "/meal_plans": "/meal_plans/4" };
  const turbo = boot(fakeNetwork(plan));
  await dispatch(turbo, fakeRequest("/", { mode: "cors" }));
  results.turboHomeCached = [...new Set(turbo.puts)].sort();
  const turboIndex = boot(fakeNetwork(plan));
  await dispatch(turboIndex, fakeRequest("/meal_plans", { mode: "cors" }));
  results.turboIndexCached = [...new Set(turboIndex.puts)].sort();

  // Browser navigations leave the redirect to the browser, so the worker looks the plan up itself.
  const navigated = boot(fakeNetwork(plan));
  await dispatch(navigated, fakeRequest("/", { mode: "navigate" }));
  results.navigateHomeCached = [...new Set(navigated.puts)].sort();
  const navigatedIndex = boot(fakeNetwork(plan));
  await dispatch(navigatedIndex, fakeRequest("/meal_plans", { mode: "navigate" }));
  results.navigateIndexCached = [...new Set(navigatedIndex.puts)].sort();
  const navigatedElsewhere = boot(fakeNetwork({ "/recipes": "/recipes/12" }));
  await dispatch(navigatedElsewhere, fakeRequest("/recipes", { mode: "navigate" }));
  results.navigateOtherRedirectNetworkCalls = navigatedElsewhere.network.calls;

  // Only those redirects write the "/" and "/meal_plans" copies: another week's plan, or a month view, must not.
  const copies = boot(fakeNetwork(plan));
  await dispatch(copies, fakeRequest("/", { mode: "cors" }));
  let mark = copies.puts.length;
  await dispatch(copies, fakeRequest("/meal_plans/9", { mode: "cors" }));
  await dispatch(copies, fakeRequest("/meal_plans/9", { mode: "navigate" }));
  await dispatch(copies, fakeRequest("/meal_plans/9/print", { mode: "navigate" }));
  await dispatch(copies, fakeRequest("/meal_plans/4?view=month", { mode: "cors" }));
  await dispatch(copies, fakeRequest("/meal_plans?view=month", { mode: "cors" }));
  results.otherPlanWrites = putsSince(copies, mark);
  goOffline(copies);
  results.homeCopyAfterOtherPlans = await text(await dispatch(copies, fakeRequest("/")));
  results.indexCopyAfterOtherPlans = await text(await dispatch(copies, fakeRequest("/meal_plans")));

  // Turbo Frame responses are fragments: never kept, and never over the full page.
  const frames = boot(online);
  await dispatch(frames, fakeRequest("/recipes/12", { mode: "navigate" }));
  mark = frames.puts.length;
  const frame = await dispatch(frames, fakeRequest("/recipes/12", { mode: "cors", headers: { "Turbo-Frame": "recipe_card" } }));
  await dispatch(frames, fakeRequest("/recipes", { mode: "cors", headers: { "Turbo-Frame": "list" } }));
  results.frameWrites = putsSince(frames, mark);
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
  results.photoCached = [...new Set(photos.puts)].sort();
  goOffline(photos);
  results.photoOffline = await text(await dispatch(photos, fakeRequest(blob, { accept: "image/*", mode: "no-cors" })));
  results.photoNeverSeenOffline = (await dispatch(photos, fakeRequest("/rails/active_storage/blobs/redirect/zzz/other.jpg", { accept: "image/*", mode: "no-cors" }))).error;

  // Offline: an allowed page that was viewed comes back from the cache, and "/" shows the current plan.
  const later = boot(fakeNetwork(plan));
  await dispatch(later, fakeRequest("/", { mode: "cors" }));
  await dispatch(later, fakeRequest("/recipes/12"));
  goOffline(later);
  results.offlineCachedRecipe = await text(await dispatch(later, fakeRequest("/recipes/12")));
  results.offlineHome = await text(await dispatch(later, fakeRequest("/")));
  results.offlinePlanIndex = await text(await dispatch(later, fakeRequest("/meal_plans")));
  results.offlinePlan = await text(await dispatch(later, fakeRequest("/meal_plans/4")));
  results.offlineHomeTurbo = await text(await dispatch(later, fakeRequest("/", { mode: "cors" })));
  const refused = {};
  for (const path of ["/platform_admin", "/account_data", "/subscription", "/recipes/99", "/grocery_list"]) {
    const reply = await dispatch(later, fakeRequest(path));
    refused[path] = { body: await text(reply), status: reply.response && reply.response.status };
  }
  results.offlineFallbacks = refused;

  // Opened offline with nothing kept yet, "/" gets the notice rather than another page.
  const empty = boot(online);
  goOffline(empty);
  const emptyHome = await dispatch(empty, fakeRequest("/"));
  results.offlineHomeEmpty = { body: await text(emptyHome), status: emptyHome.response && emptyHome.response.status };

  // Only a navigation gets the notice page; a Turbo or script fetch gets the network error.
  const scripted = {};
  for (const path of ["/recipes/99", "/account_data", "/"]) {
    const reply = await dispatch(empty, fakeRequest(path, { mode: "cors" }));
    scripted[path] = { error: reply.error, intercepted: reply.intercepted, response: reply.response === null };
  }
  results.offlineNonNavigation = scripted;

  // Activate deletes older cache versions and keeps its own.
  const upgraded = boot(online);
  await upgraded.caches.open("familyplates-v1");
  await upgraded.caches.open("familyplates-v2");
  await upgraded.caches.open("familyplates-v3");
  let installing;
  upgraded.listeners.install({ waitUntil: (p) => { installing = p; } });
  await installing;
  let activation;
  upgraded.listeners.activate({ waitUntil: (p) => { activation = p; } });
  await activation;
  results.cachesAfterActivate = await upgraded.caches.keys();

  console.log(JSON.stringify(results));
}

run().catch((error) => { console.error(error); process.exit(1); });
