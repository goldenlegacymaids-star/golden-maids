import type { NextConfig } from "next";

/**
 * Golden Maids staff website.
 *
 * Built as static files (`out/`), so it can be hosted anywhere without a
 * server. All data access happens in the browser through Supabase, and Row
 * Level Security decides what each staff role may read or change.
 */
const nextConfig: NextConfig = {
  output: "export",
  // `/candidates` is written as `/candidates/index.html`, which every static
  // host serves without extra configuration.
  trailingSlash: true,
  images: { unoptimized: true },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
