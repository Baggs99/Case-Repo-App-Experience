/**
 * Upload selected split case PDFs under ``output/cases/`` to Cloudflare R2.
 *
 * Object keys match storage layout (no ``cases/`` prefix):
 *   Yale/Fuqua 2017/yahtco.pdf
 *
 * Env (same as upload-previews-to-r2.ts):
 *   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
 *   R2_BUCKET_NAME         — default case-repo-pdfs
 *   R2_ENDPOINT            — OR build from R2_ACCOUNT_ID
 *
 * Optional:
 *   CASES_LOCAL_ROOT       — default output/cases (repo-relative or absolute)
 *
 * Usage:
 *   npm run upload:cases -- --dry-run --only-source "Yale/Fuqua 2017"
 *   npm run upload:cases -- --only-source "Yale/Fuqua 2017"
 */

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import dotenv from "dotenv";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

dotenv.config({ path: path.join(REPO_ROOT, ".env") });

const CACHE_CONTROL = "public, max-age=31536000, immutable";

function r2Endpoint(): string {
  const ep = process.env.R2_ENDPOINT?.trim();
  if (ep) return ep.replace(/\/+$/, "");
  const aid = process.env.R2_ACCOUNT_ID?.trim();
  if (!aid) {
    throw new Error("Set R2_ENDPOINT or R2_ACCOUNT_ID for R2 S3 API endpoint.");
  }
  return `https://${aid}.r2.cloudflarestorage.com`;
}

function normPrefix(s: string): string {
  return s.replace(/\\/g, "/").replace(/^\/+/, "").replace(/\/+$/, "");
}

function parseCli(): { dryRun: boolean; onlySource: string } {
  const argv = process.argv.slice(2);
  let dryRun = false;
  let onlySource: string | undefined;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") {
      dryRun = true;
      continue;
    }
    if (a === "--only-source") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) {
        console.error("--only-source requires a path prefix value.");
        process.exit(1);
      }
      onlySource = normPrefix(v);
      continue;
    }
  }

  if (!onlySource) {
    console.error(
      'Usage: npm run upload:cases -- --only-source "Yale/Fuqua 2017" [--dry-run]',
    );
    process.exit(1);
  }

  return { dryRun, onlySource };
}

function relPosixFromCasesRoot(absFile: string, casesRoot: string): string {
  return path.relative(casesRoot, absFile).split(path.sep).join("/");
}

function keyMatchesOnlySource(relKey: string, prefix: string): boolean {
  const p = prefix.replace(/\/+$/, "");
  return relKey === p || relKey.startsWith(`${p}/`);
}

async function collectPdfFiles(casesRoot: string): Promise<string[]> {
  const out: string[] = [];

  async function walk(absDir: string): Promise<void> {
    let entries;
    try {
      entries = await readdir(absDir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(absDir, e.name);
      if (e.isDirectory()) {
        if (e.name.startsWith(".")) continue;
        await walk(full);
      } else if (e.isFile() && e.name.toLowerCase().endsWith(".pdf")) {
        out.push(full);
      }
    }
  }

  await walk(casesRoot);
  out.sort();
  return out;
}

async function main(): Promise<void> {
  const { dryRun, onlySource } = parseCli();

  const casesRel = process.env.CASES_LOCAL_ROOT?.trim() || path.join("output", "cases");
  const casesRoot = path.isAbsolute(casesRel)
    ? casesRel
    : path.join(REPO_ROOT, casesRel);

  try {
    await stat(casesRoot);
  } catch {
    console.error("Cases folder not found:", casesRoot);
    process.exit(1);
  }

  const bucket = process.env.R2_BUCKET_NAME?.trim() || "case-repo-pdfs";
  const accessKeyId = process.env.R2_ACCESS_KEY_ID?.trim();
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY?.trim();

  if (!dryRun && (!accessKeyId || !secretAccessKey)) {
    console.error("R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY are required unless --dry-run.");
    process.exit(1);
  }

  const allPdfs = await collectPdfFiles(casesRoot);

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

  let uploaded = 0;
  let skipped = 0;

  for (const absPath of allPdfs) {
    const objectKey = relPosixFromCasesRoot(absPath, casesRoot);

    if (!keyMatchesOnlySource(objectKey, onlySource)) {
      skipped++;
      continue;
    }

    const body = await readFile(absPath);

    if (dryRun) {
      console.log(`[dry-run] ${objectKey} (${body.length} bytes)`);
    } else {
      await client!.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: objectKey,
          Body: body,
          ContentType: "application/pdf",
          CacheControl: CACHE_CONTROL,
        }),
      );
      console.log(`uploaded ${objectKey}`);
    }
    uploaded++;
  }

  console.log("\n=== summary ===");
  console.log("--only-source:", onlySource);
  console.log("cases root:", casesRoot);
  console.log("pdf files scanned:", allPdfs.length);
  console.log(dryRun ? "would upload:" : "uploaded:", uploaded);
  console.log("skipped (outside filter):", skipped);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
