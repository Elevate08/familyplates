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
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    launchOptions: {
      executablePath: "/usr/bin/chromium",
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

  webServer: {
    command: "bin/rails server -e test -p 3100",
    url: "http://127.0.0.1:3100/up",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    env: {
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
