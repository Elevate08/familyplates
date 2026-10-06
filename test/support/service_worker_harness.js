// Runs the rendered service worker (stdin) against fake caches and a fake
// network, then prints what it did as JSON. Used by ServiceWorkerBehaviourTest;
// nothing here ships to the browser.
const vm = require("vm");
const fs = require("fs");

const source = fs.readFileSync(0, "utf8");
const ORIGIN = "http://localhost";

function fakeRequest(path, { accept = "text/html", mode = "navigate", method = "GET", origin = ORIGIN } = {}) {
  return {
    method,
    url: origin + path,
    mode,
    headers: { get: (name) => (name.toLowerCase() === "accept" ? accept : null) }
  };
}

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
  const context = { self, caches, URL, Response, console: { warn() {}, log() {} }, fetch: (req) => network.fetch(req) };
  vm.runInNewContext(source, context);
  return { listeners, caches, puts, stores };
}

async function dispatch(worker, request) {
  let responded;
  const event = { request, respondWith: (promise) => { responded = promise; } };
  worker.listeners.fetch(event);
  const response = responded ? await responded : null;
  await new Promise((resolve) => setTimeout(resolve, 0));
  return { intercepted: responded !== undefined, response };
}

async function run() {
  const results = {};
  const online = { fetch: async (req) => new Response("network " + new URL(req.url).pathname) };
  const offline = { fetch: async () => { throw new TypeError("offline"); } };

  // Online: which GETs end up in the cache?
  const worker = boot(online);
  const probes = {
    html: [
      "/", "/grocery_list", "/grocery_list/3", "/grocery_list/current", "/recipes", "/recipes/12", "/recipes/12/cook",
      "/meal_plans", "/meal_plans/4", "/meal_plans/4/print", "/recipes/new", "/recipes/12/edit", "/meal_plans/new",
      "/meal_plans/4/edit", "/platform_admin", "/platform_admin/households", "/account_data", "/subscription",
      "/support/threads", "/preferences/edit", "/session/new", "/devices", "/pair", "/admin", "/activity", "/pantry_items"
    ],
    other: ["/account_data/export", "/calendars/feed/abc", "/rails/active_storage/blobs/x/photo.png", "/up"],
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

  // A redirected response (for example /grocery_list bounced to sign-in) is never kept.
  const bounced = boot({ fetch: async () => { const r = new Response("sign in"); Object.defineProperty(r, "redirected", { value: true }); return r; } });
  await dispatch(bounced, fakeRequest("/grocery_list"));
  results.redirectedCached = bounced.puts.length > 0;

  // Offline: an allowed page that was viewed comes back from the cache; "/" is cached too.
  const later = boot(online);
  await dispatch(later, fakeRequest("/"));
  await dispatch(later, fakeRequest("/recipes/12"));
  await dispatch(later, fakeRequest("/meal_plans/4"));
  const nowOffline = later;
  const wasOnline = online.fetch;
  online.fetch = offline.fetch;
  const text = async (r) => (r.response ? r.response.text() : null);
  results.offlineCachedRecipe = await text(await dispatch(nowOffline, fakeRequest("/recipes/12")));
  results.offlinePlanIndex = await text(await dispatch(nowOffline, fakeRequest("/meal_plans")));
  const refused = {};
  for (const path of ["/platform_admin", "/account_data", "/subscription", "/recipes/99", "/grocery_list"]) {
    const reply = await dispatch(nowOffline, fakeRequest(path));
    refused[path] = { body: await text(reply), status: reply.response && reply.response.status };
  }
  results.offlineFallbacks = refused;
  online.fetch = wasOnline;

  // Activate deletes older cache versions and keeps its own.
  const upgraded = boot(online);
  await upgraded.caches.open("familyplates-v1");
  await upgraded.caches.open("familyplates-v2");
  let installing;
  upgraded.listeners.install({ waitUntil: (p) => { installing = p; } });
  await installing;
  const keysBefore = await upgraded.caches.keys();
  let activation;
  upgraded.listeners.activate({ waitUntil: (p) => { activation = p; } });
  await activation;
  results.cachesBefore = keysBefore;
  results.cachesAfterActivate = await upgraded.caches.keys();

  console.log(JSON.stringify(results));
}

run().catch((error) => { console.error(error); process.exit(1); });
