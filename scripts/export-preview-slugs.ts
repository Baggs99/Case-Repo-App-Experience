/**
 * Export ``cases.pdf_path`` and ``cases.preview_public_slug`` to CSV for local upload.
 *
 * Intended for Render Shell where Postgres is reachable.
 *
 * Output: ``output/preview_slug_map.csv`` (relative to repo root)
 *
 * Env: DATABASE_URL (required)
 */

import dotenv from "dotenv";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { csvEscape } from "./csv_slug_map.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

dotenv.config({ path: path.join(REPO_ROOT, ".env") });

async function main(): Promise<void> {
  const dbUrl = process.env.DATABASE_URL?.trim();
  if (!dbUrl) {
    console.error("DATABASE_URL is required.");
    process.exit(1);
  }

  const outRel = process.env.PREVIEW_SLUG_MAP_OUTPUT?.trim() || "output/preview_slug_map.csv";
  const outPath = path.isAbsolute(outRel) ? outRel : path.join(REPO_ROOT, outRel);

  const pool = new Pool({ connectionString: dbUrl });
  try {
    const { rows } = await pool.query<{
      pdf_path: string;
      preview_public_slug: string;
    }>(
      `SELECT pdf_path, preview_public_slug FROM cases
       WHERE pdf_path IS NOT NULL AND preview_public_slug IS NOT NULL
       ORDER BY pdf_path`,
    );

    const lines = ["pdf_path,preview_public_slug"];
    for (const row of rows) {
      lines.push(`${csvEscape(row.pdf_path.replace(/\\/g, "/"))},${csvEscape(row.preview_public_slug)}`);
    }

    await mkdir(path.dirname(outPath), { recursive: true });
    await writeFile(outPath, lines.join("\n") + "\n", "utf-8");

    console.log(`Wrote ${rows.length} rows to ${outPath}`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
