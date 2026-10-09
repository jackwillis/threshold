// Bundles src/app.ts into priv/static/assets. `bun build.ts [--watch]`; set NODE_ENV=production to minify.
import { cp, mkdir } from "node:fs/promises";
import { watch } from "node:fs";

const production = process.env.NODE_ENV === "production";
const outdir = "../priv/static/assets";

async function build() {
  const result = await Bun.build({
    entrypoints: ["src/app.ts"],
    outdir: `${outdir}/js`,
    naming: "app.js",
    minify: production,
    sourcemap: production ? "none" : "linked",
    target: "browser",
  });
  if (!result.success) {
    for (const log of result.logs) console.error(log);
    return false;
  }
  await mkdir(`${outdir}/css`, { recursive: true });
  await cp("node_modules/maplibre-gl/dist/maplibre-gl.css", `${outdir}/css/maplibre-gl.css`);
  console.log(`built ${new Date().toLocaleTimeString()}`);
  return true;
}

const ok = await build();
if (process.argv.includes("--watch")) {
  watch("src", { recursive: true }, () => void build());
} else if (!ok) {
  process.exit(1);
}
