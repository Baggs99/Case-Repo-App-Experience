/**
 * Upload ``output/previews_local/<catalog-mirror>/`` JPEGs to Cloudflare R2.
 *
 * Object layout (bucket root):
 *   previews/<preview_public_slug>/page-001.jpg
 *   previews/<preview_public_slug>/preview-knit.jpg   (optional)
 *
 * Matching: local folder ``School/Book/case-slug`` ↔ DB ``pdf_path`` ``School/Book/case-slug.pdf``
 *
 * Env:
 *   DATABASE_URL           — Postgres (same as production cases table)
 *   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
 *   R2_BUCKET_NAME         — default case-repo-pdfs
 *   R2_ENDPOINT            — OR build from R2_ACCOUNT_ID
 *   R2_ACCOUNT_ID          — optional if R2_ENDPOINT set
 *   PREVIEWS_LOCAL_ROOT    — optional, default output/previews_local (relative to repo root)
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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

dotenv.config({ path: path.join(REPO_ROOT, ".env") });

const CACHE_CONTROL = "public, max-age=31536000, immutable";

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

async function main(): Promise<void> {
  const dryRun = process.argv.includes("--dry-run");

  const previewsRel = process.env.PREVIEWS_LOCAL_ROOT?.trim() || "output/previews_local";
  const previewsRoot = path.isAbsolute(previewsRel)
    ? previewsRel
    : path.join(REPO_ROOT, previewsRel);

  const dbUrl = process.env.DATABASE_URL?.trim();
  if (!dbUrl) {
    console.error("DATABASE_URL is required for slug ↔ pdf_path matching.");
    process.exit(1);
  }

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

  const pool = new Pool({ connectionString: dbUrl });
  let client: S3Client | null = null;
  if (!dryRun) {
    client = new S3Client({
      region: "auto",
      endpoint: r2Endpoint(),
      credentials: {
        accessKeyId: accessKeyId!,
        secretAccessKey: secretAccessKey!,
      },
    });
  }

  let matched = 0;
  let filesUploaded = 0;
  const unmatchedLocal: string[] = [];
  const matchedPdfPaths = new Set<string>();
  let unmatchedDb: string[] = [];

  try {
    const { rows } = await pool.query<{
      pdf_path: string;
      preview_public_slug: string;
    }>(
      `SELECT pdf_path, preview_public_slug FROM cases
       WHERE pdf_path IS NOT NULL AND preview_public_slug IS NOT NULL`,
    );

    const pdfToSlug = new Map<string, string>();
    for (const row of rows) {
      pdfToSlug.set(normPdfKey(row.pdf_path), row.preview_public_slug);
    }

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

    for (const [pdfPath, slug] of pdfToSlug) {
      if (!matchedPdfPaths.has(pdfPath)) {
        unmatchedDb.push(`${pdfPath} → ${slug}`);
      }
    }
  } finally {
    await pool.end();
  }

  console.log("\n=== summary ===");
  console.log("cases matched & processed:", matched);
  console.log("files " + (dryRun ? "would upload" : "uploaded") + ":", filesUploaded);
  console.log("unmatched local folders:", unmatchedLocal.length);
  if (unmatchedLocal.length) {
    console.log(
      unmatchedLocal.slice(0, 40).join("\n") + (unmatchedLocal.length > 40 ? "\n…" : ""),
    );
  }
  console.log("DB pdf_paths with no local previews folder:", unmatchedDb.length);
  if (unmatchedDb.length && unmatchedDb.length <= 30) {
    console.log(unmatchedDb.join("\n"));
  } else if (unmatchedDb.length > 30) {
    console.log(unmatchedDb.slice(0, 30).join("\n") + "\n…");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
