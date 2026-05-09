/**
 * Upload ``output/previews_local/<catalog-mirror>/`` JPEGs to Cloudflare R2.
 *
 * Object layout (bucket root):
 *   previews/<preview_public_slug>/page-001.jpg
 *   previews/<preview_public_slug>/preview-knit.jpg   (optional)
 *
 * Matching: local folder ``School/Book/case-slug`` ↔ ``pdf_path`` ``School/Book/case-slug.pdf``
 *
 * Slug ↔ pdf mapping (first match wins):
 *   1. If ``output/preview_slug_map.csv`` exists (override: PREVIEW_SLUG_MAP_CSV), load it — **no Postgres**.
 *   2. Else query ``DATABASE_URL`` (cases table).
 *
 * Env:
 *   DATABASE_URL           — Postgres (when CSV missing)
 *   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
 *   R2_BUCKET_NAME         — default case-repo-pdfs
 *   R2_ENDPOINT            — OR build from R2_ACCOUNT_ID
 *   PREVIEWS_LOCAL_ROOT    — optional, default output/previews_local
 *   PREVIEW_SLUG_MAP_CSV   — optional path to slug map CSV (repo-relative or absolute)
 *
 * Usage:
 *   npm run upload:previews -- --dry-run
 *   npm run upload:previews
 */

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import dotenv from "dotenv";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { parseSlugMapCsv } from "./csv_slug_map.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

dotenv.config({ path: path.join(REPO_ROOT, ".env") });

const CACHE_CONTROL = "public, max-age=31536000, immutable";

const DEFAULT_MAP_REL = path.join("output", "preview_slug_map.csv");

function resolveSlugMapCsvPath(): string {
  const env = process.env.PREVIEW_SLUG_MAP_CSV?.trim();
  if (env) {
    return path.isAbsolute(env) ? env : path.join(REPO_ROOT, env);
  }
  return path.join(REPO_ROOT, DEFAULT_MAP_REL);
}

function normPdfKey(p: string): string {
  return p.replace(/\\/g, "/").trim();
}

function relPosix(absDir: string, previewsRoot: string): string {
  return path.relative(previewsRoot, absDir).split(path.sep).join("/");
}

async function collectCaseFolders(previewsRoot: string): Promise<string[]> {
  const results: string[] = [];

  async function walk(absDir: string): Promise<void> {
    let entries;
    try {
      entries = await readdir(absDir, { withFileTypes: true });
    } catch {
      return;
    }
    const hasPage1 = entries.some((e) => e.isFile() && e.name === "page-001.jpg");
    if (hasPage1) {
      results.push(relPosix(absDir, previewsRoot));
      return;
    }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      if (e.name.startsWith(".")) continue;
      await walk(path.join(absDir, e.name));
    }
  }

  await walk(previewsRoot);
  results.sort();
  return results;
}

async function collectUploadFiles(absCaseDir: string): Promise<string[]> {
  const names = await readdir(absCaseDir);
  const pages = names
    .filter((n) => /^page-\d+\.jpg$/i.test(n))
    .sort((a, b) => {
      const na = parseInt(/^page-(\d+)/i.exec(a)?.[1] ?? "0", 10);
      const nb = parseInt(/^page-(\d+)/i.exec(b)?.[1] ?? "0", 10);
      return na - nb;
    });
  const out = [...pages];
  if (names.some((n) => n.toLowerCase() === "preview-knit.jpg")) {
    out.push("preview-knit.jpg");
  }
  return out;
}

function r2Endpoint(): string {
  const ep = process.env.R2_ENDPOINT?.trim();
  if (ep) return ep.replace(/\/+$/, "");
  const aid = process.env.R2_ACCOUNT_ID?.trim();
  if (!aid) {
    throw new Error("Set R2_ENDPOINT or R2_ACCOUNT_ID for R2 S3 API endpoint.");
  }
  return `https://${aid}.r2.cloudflarestorage.com`;
}

async function loadPdfToSlugMap(): Promise<{ map: Map<string, string>; source: "csv" | "db" }> {
  const csvPath = resolveSlugMapCsvPath();
  try {
    await stat(csvPath);
    const content = await readFile(csvPath, "utf-8");
    console.log(`Using slug map CSV (no Postgres): ${csvPath}`);
    return { map: parseSlugMapCsv(content), source: "csv" };
  } catch (e: unknown) {
    if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
  }

  const dbUrl = process.env.DATABASE_URL?.trim();
  if (!dbUrl) {
    console.error(
      "No slug map CSV found and DATABASE_URL is not set.\n" +
        `  Expected CSV at: ${csvPath}\n` +
        "  Or export on Render: npm run export:preview-slugs → copy CSV locally.",
    );
    process.exit(1);
  }

  console.log(`Using Postgres DATABASE_URL slug map`);

  const pool = new Pool({ connectionString: dbUrl });
  try {
    const { rows } = await pool.query<{
      pdf_path: string;
      preview_public_slug: string;
    }>(
      `SELECT pdf_path, preview_public_slug FROM cases
       WHERE pdf_path IS NOT NULL AND preview_public_slug IS NOT NULL`,
    );
    const map = new Map<string, string>();
    for (const row of rows) {
      map.set(normPdfKey(row.pdf_path), row.preview_public_slug);
    }
    return { map, source: "db" };
  } finally {
    await pool.end();
  }
}

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");

  const previewsRel = process.env.PREVIEWS_LOCAL_ROOT?.trim() || "output/previews_local";
  const previewsRoot = path.isAbsolute(previewsRel)
    ? previewsRel
    : path.join(REPO_ROOT, previewsRel);

  try {
    await stat(previewsRoot);
  } catch {
    console.error("Previews folder not found:", previewsRoot);
    process.exit(1);
  }

  const bucket = process.env.R2_BUCKET_NAME?.trim() || "case-repo-pdfs";
  const accessKeyId = process.env.R2_ACCESS_KEY_ID?.trim();
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY?.trim();

  if (!dryRun && (!accessKeyId || !secretAccessKey)) {
    console.error("R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY are required unless --dry-run.");
    process.exit(1);
  }

  const { map: pdfToSlug, source: mapSource } = await loadPdfToSlugMap();

  const client =
    dryRun ?
      null
    : new S3Client({
        region: "auto",
        endpoint: r2Endpoint(),
        credentials: {
          accessKeyId: accessKeyId!,
          secretAccessKey: secretAccessKey!,
        },
      });

  let matched = 0;
  let filesUploaded = 0;
  const unmatchedLocal: string[] = [];
  const matchedPdfPaths = new Set<string>();
  let unmatchedMapped: string[] = [];

  const folders = await collectCaseFolders(previewsRoot);

  for (const folderRel of folders) {
    if (!folderRel) continue;
    const pdfPathKey = normPdfKey(`${folderRel}.pdf`);
    const slug = pdfToSlug.get(pdfPathKey);
    if (!slug) {
      unmatchedLocal.push(folderRel);
      continue;
    }
    matched++;
    matchedPdfPaths.add(pdfPathKey);

    const absCaseDir = path.join(previewsRoot, folderRel.split("/").join(path.sep));
    const files = await collectUploadFiles(absCaseDir);

    for (const fname of files) {
      const objectKey = `previews/${slug}/${fname}`;
      const absFile = path.join(absCaseDir, fname);
      const body = await readFile(absFile);

      if (dryRun) {
        console.log(`[dry-run] ${objectKey} (${body.length} bytes)`);
      } else {
        await client!.send(
          new PutObjectCommand({
            Bucket: bucket,
            Key: objectKey,
            Body: body,
            ContentType: "image/jpeg",
            CacheControl: CACHE_CONTROL,
          }),
        );
        console.log(`uploaded ${objectKey}`);
      }
      filesUploaded++;
    }
  }

  for (const pdfPath of pdfToSlug.keys()) {
    if (!matchedPdfPaths.has(pdfPath)) {
      unmatchedMapped.push(`${pdfPath} → ${pdfToSlug.get(pdfPath)}`);
    }
  }

  console.log("\n=== summary ===");
  console.log("slug map source:", mapSource);
  console.log("cases matched & processed:", matched);
  console.log("files " + (dryRun ? "would upload" : "uploaded") + ":", filesUploaded);
  console.log("unmatched local folders:", unmatchedLocal.length);
  if (unmatchedLocal.length) {
    console.log(
      unmatchedLocal.slice(0, 40).join("\n") + (unmatchedLocal.length > 40 ? "\n…" : ""),
    );
  }
  const orphanLabel =
    mapSource === "csv" ? "CSV rows with no local previews folder" : "DB pdf_paths with no local previews folder";
  console.log(`${orphanLabel}:`, unmatchedMapped.length);
  if (unmatchedMapped.length && unmatchedMapped.length <= 30) {
    console.log(unmatchedMapped.join("\n"));
  } else if (unmatchedMapped.length > 30) {
    console.log(unmatchedMapped.slice(0, 30).join("\n") + "\n…");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
