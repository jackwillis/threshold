import { mkdir, readFile, writeFile } from "node:fs/promises";
import { MATERIALS, materialId } from "../src/map/atlas/materials";
import { SEASONS, SEASON_TOKENS } from "../src/map/atlas/tokens";
import { generateMaterial, png } from "./watercolor";

export async function buildMaterials(check = false): Promise<void> {
  const dir = new URL("../../priv/static/assets/materials/", import.meta.url);
  if (!check) await mkdir(dir, { recursive: true });
  for (const season of SEASONS) for (const material of MATERIALS) {
    const t = SEASON_TOKENS[season]; const file = new URL(`${materialId(material, t)}.png`, dir);
    const bytes = png(generateMaterial(material, t));
    if (check) {
      if (!bytes.equals(await readFile(file))) throw new Error(`Stale material: ${file.pathname}. Run bun run materials.`);
    } else await writeFile(file, bytes);
  }
}
if (import.meta.main) await buildMaterials(process.argv.includes("--check"));
