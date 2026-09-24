import { defineConfig } from "@playwright/test";
import fs from "node:fs";
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
  fullyParallel: false,
  workers: 1, // Single worker ensures deterministic database resets against the local SQLite database
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: "http://127.0.0.1:3100",
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

  // Its own database file: resets and sign-ins leave rows in tables that have no
  // fixtures (sessions, platform-admin accounts), and in storage/test.sqlite3
  // those broke Minitest runs that count them. db:prepare builds the file on a
  // fresh checkout and migrates it after a pull.
  webServer: {
    command: "bin/rails db:prepare && bin/rails server -p 3100",
    url: "http://127.0.0.1:3100/up",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    env: {
      RAILS_ENV: "test",
      TEST_DATABASE_PATH: "storage/e2e.sqlite3",
      ENABLE_REAL_STRIPE_TESTS: process.env.ENABLE_REAL_STRIPE_TESTS || "",
      STRIPE_PRIVATE_KEY: process.env.STRIPE_PRIVATE_KEY || "",
      STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY || "",
      STRIPE_PUBLISHABLE_KEY: process.env.STRIPE_PUBLISHABLE_KEY || "",
      STRIPE_SIGNING_SECRET: process.env.STRIPE_SIGNING_SECRET || "",
      STRIPE_MONTHLY_PRICE_ID: process.env.STRIPE_MONTHLY_PRICE_ID || "",
      STRIPE_ANNUAL_PRICE_ID: process.env.STRIPE_ANNUAL_PRICE_ID || ""
    }
  }
});
