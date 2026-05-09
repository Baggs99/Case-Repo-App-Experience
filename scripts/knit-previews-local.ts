/**
 * Stack ``page-NNN.jpg`` into ``preview-knit.jpg`` per case folder (Pillow).
 *
 * Wraps: ``python main.py knit-previews-local`` — see main.py for options.
 *
 *   npm run knit-previews-local -- --only-source "Yale/Fuqua 2017"
 *   npm run knit-previews-local -- --skip-existing
 *
 * Env: ``PYTHON`` overrides the Python executable (default ``python``).
 */

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

const py = process.env.PYTHON?.trim() || "python";
const args = ["main.py", "knit-previews-local", ...process.argv.slice(2)];

const r = spawnSync(py, args, {
  cwd: REPO_ROOT,
  stdio: "inherit",
  env: process.env,
});

process.exit(r.status === null || r.signal ? 1 : r.status);
