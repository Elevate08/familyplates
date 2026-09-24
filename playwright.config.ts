import { defineConfig } from "@playwright/test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// Load local environment files if present
for (const envFile of [".env.test.local", ".env.local"]) {
  const fullPath = path.resolve(__dirname, envFile);
  if (fs.existsSync(fullPath)) {
    try {
      process.loadEnvFile(fullPath);
    } catch {
      // Ignore parse errors if file is malformed
    }
  }
}

// The real-checkout test creates a customer and pays with a test card. Given a
// live key it would do that to the real Stripe account, so a run with one
// stops here, before the web server is handed the key. The Rails test
// environment makes the same check at boot (FamilyPlates::StripeSandbox).
const STRIPE_SANDBOX_KEY = /^(sk|rk|pk)_test_/;
for (const name of ["STRIPE_SECRET_KEY", "STRIPE_PRIVATE_KEY", "STRIPE_PUBLISHABLE_KEY", "STRIPE_PUBLIC_KEY"]) {
  const key = process.env[name];
  if (key && !STRIPE_SANDBOX_KEY.test(key)) {
    throw new Error(`${name} is not a Stripe test key (sk_test_, rk_test_ or pk_test_). E2E runs use a Stripe sandbox only.`);
  }
}

// Where the browser comes from, in order of preference:
//
// 1. PLAYWRIGHT_WS_ENDPOINT - a browser already running in the pinned Playwright
//    container (bin/e2e starts one). This is what CI uses and what the committed
//    screenshot baselines are recorded against; see bin/e2e-browser-server.
// 2. PLAYWRIGHT_CHROMIUM_PATH - a system Chromium, e.g. /usr/bin/chromium on
//    Arch where Playwright's bundled build has no matching libraries.
// 3. Playwright's bundled Chromium (`npx playwright install chromium`).
//
// Only (1) is expected to match the baselines. The other two render with
// whatever fonts the machine has, so they are for debugging flows, not for
// judging a screenshot diff.
const wsEndpoint = process.env.PLAYWRIGHT_WS_ENDPOINT;
const chromiumPath = process.env.PLAYWRIGHT_CHROMIUM_PATH;

// Workers run side by side, each against its own Rails server and SQLite file:
// a test resets the database and sets the server's mode and clock, so two
// workers sharing one would undo each other mid-test. Worker N (Playwright's
// parallel index, stable for the life of the run) talks to port 3100 + N.
//
// This file is evaluated again inside each worker, where Playwright has set
// TEST_PARALLEL_INDEX, which is how baseURL below picks the worker's server.
//
// One worker per four CPUs. A single worker's Chromium already keeps about
// four busy - it renders across several processes and threads - so more
// workers only take turns: on four CPUs the crawl took 167s with one worker
// and 157-166s with two to four, each test several times slower. GitHub's
// 4-CPU runner therefore runs one; a 16-core machine runs four, 2.2x faster.
// availableParallelism honours CPU affinity, so a pinned run is sized right.
const WORKERS = Number(process.env.E2E_WORKERS || Math.max(1, Math.floor(os.availableParallelism() / 4)));
const FIRST_PORT = 3100;
const serverPort = (index: number) => FIRST_PORT + index;
const parallelIndex = Number(process.env.TEST_PARALLEL_INDEX ?? 0);

export default defineConfig({
  testDir: "./e2e",
  snapshotPathTemplate: "{testDir}/snapshots/{projectName}/{testFilePath}/{arg}{ext}",
  timeout: 30_000,
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.002,
      animations: "disabled"
    }
  },
  // A file runs start to finish in one worker, so a spec's beforeAll reset
  // holds for its tests. The route crawl is split into a file per role
  // (e2e/crawl/) so its visits spread across the workers.
  fullyParallel: false,
  workers: WORKERS,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: `http://127.0.0.1:${serverPort(parallelIndex)}`,
    // Kept for every failure, not only a retried one, so a CI failure can be
    // replayed from the uploaded report without reproducing it locally.
    trace: "retain-on-failure",
    // Recording needs Playwright's own ffmpeg, which the container and a
    // `playwright install chromium` both have and a system Chromium does not.
    video: chromiumPath ? "off" : "retain-on-failure",
    screenshot: "only-on-failure",
    // exposeNetwork sends the container's requests for 127.0.0.1 back through
    // this process, so the browser reaches the Rails server without the
    // container sharing the host's network.
    ...(wsEndpoint ? { connectOptions: { wsEndpoint, exposeNetwork: "<loopback>" } } : {}),
    // Apply to a local browser only: a remote browser server does not take
    // Chromium args from its clients. The container needs none to be consistent.
    launchOptions: {
      ...(chromiumPath ? { executablePath: chromiumPath } : {}),
      args: [
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--font-render-hinting=none",
        "--disable-font-subpixel-positioning",
        "--disable-lcd-text"
      ]
    }
  },

  projects: [
    {
      name: "desktop-light",
      use: {
        viewport: { width: 1400, height: 900 },
        colorScheme: "light"
      }
    },
    {
      name: "desktop-dark",
      // The crawl's checks - server errors, script errors, broken images - come
      // from the same code in either colour scheme, and axe runs on
      // desktop-light only, so crawling again in dark repeated a quarter of the
      // run to learn nothing new. Dark is still held to its screenshots and flows.
      testIgnore: /crawl\//,
      use: {
        viewport: { width: 1400, height: 900 },
        colorScheme: "dark"
      }
    },
    {
      name: "mobile-light",
      use: {
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
        colorScheme: "light"
      }
    }
  ],

  // Each worker's server has its own database file: resets and sign-ins leave
  // rows in tables that have no fixtures (sessions, platform-admin accounts),
  // and in storage/test.sqlite3 those broke Minitest runs that count them.
  // db:prepare builds the file on a fresh checkout and migrates it after a
  // pull. Each server also needs its own pid file, or the second refuses to
  // start while the first holds tmp/pids/server.pid.
  webServer: Array.from({ length: WORKERS }, (_, index) => ({
    command: `bin/rails db:prepare && bin/rails server -p ${serverPort(index)} -P tmp/pids/e2e-${index}.pid`,
    url: `http://127.0.0.1:${serverPort(index)}/up`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      RAILS_ENV: "test",
      TEST_DATABASE_PATH: `storage/e2e-${index}.sqlite3`,
      ENABLE_REAL_STRIPE_TESTS: process.env.ENABLE_REAL_STRIPE_TESTS || "",
      STRIPE_PRIVATE_KEY: process.env.STRIPE_PRIVATE_KEY || "",
      STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY || "",
      STRIPE_PUBLISHABLE_KEY: process.env.STRIPE_PUBLISHABLE_KEY || "",
      STRIPE_PUBLIC_KEY: process.env.STRIPE_PUBLIC_KEY || "",
      STRIPE_SIGNING_SECRET: process.env.STRIPE_SIGNING_SECRET || "",
      STRIPE_MONTHLY_PRICE_ID: process.env.STRIPE_MONTHLY_PRICE_ID || "",
      STRIPE_ANNUAL_PRICE_ID: process.env.STRIPE_ANNUAL_PRICE_ID || ""
    }
  }))
});
