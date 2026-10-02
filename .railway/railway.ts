import {
  defineRailway,
  github,
  postgres,
  project,
  service,
} from "railway/iac";

// Starter Railway Infrastructure as Code for Paperclip.
// This describes the same architecture as docker/docker-compose.yml:
// - Dedicated Postgres database
// - Paperclip app built from the root Dockerfile (serves UI + API)
// - Key environment wiring
//
// After editing, run:
//   railway config plan
//   railway config apply   (only when ready)
//
// To turn this into a shareable one-click template:
// 1. Deploy once (or use this config)
// 2. In Railway dashboard: Project Settings → "Generate Template from Project"
// 3. In the template editor, configure variables (use ${{ secret(32, "hex") }} for BETTER_AUTH_SECRET)
// 4. Publish the template to the marketplace.

export default defineRailway(() => {
  // Managed Postgres (equivalent to the "db" service in docker-compose.yml)
  const db = postgres("paperclip-db");

  // Main Paperclip service.
  // Because a Dockerfile exists at the repo root, Railway will use Docker build.
  // Update the GitHub source below to match your fork if needed
  // (e.g. "your-org/paperclip").
  const paperclip = service("paperclip", {
    source: github("The-HOLE-Foundation/paperclip"),
    // Explicitly prefer Dockerfile builder when both options could apply
    builder: "DOCKERFILE",

    // Health check (the app exposes /health)
    healthcheck: "/health",

    // Core environment. Use references for DATABASE_URL.
    // For BETTER_AUTH_SECRET and PAPERCLIP_PUBLIC_URL, you will typically
    // configure them with template secret() helpers or static values when
    // publishing the template (or set them after the first deploy).
    env: {
      DATABASE_URL: db.env.DATABASE_URL,

      // Deployment mode for a public cloud instance
      PAPERCLIP_DEPLOYMENT_MODE: "authenticated",
      PAPERCLIP_DEPLOYMENT_EXPOSURE: "public",

      // Serve the bundled UI from the same process
      SERVE_UI: "true",

      // Listen on all interfaces inside the container
      HOST: "0.0.0.0",

      // Automatically apply migrations on boot (safe for first deploy)
      PAPERCLIP_MIGRATION_AUTO_APPLY: "true",

      // PAPERCLIP_PUBLIC_URL should be set to the public domain of this service.
      // After deploy you can reference the generated domain or hard-code a custom one.
      // PAPERCLIP_PUBLIC_URL: "https://your-custom-domain.example.com",

      // BETTER_AUTH_SECRET should be a long random secret.
      // When creating/publishing a template, set it in the Variables tab using:
      //   ${{ secret(32, "hex") }}
      // or generate once and mark the variable as secret.
      // BETTER_AUTH_SECRET: "<will-be-set-at-deploy-time>",
    },
  });

  // Return the project definition.
  // You can wrap resources in group("Frontend", [...]) etc. for organization.
  return project("paperclip", {
    resources: [db, paperclip],
  });
});
