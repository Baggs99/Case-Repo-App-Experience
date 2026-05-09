/**
 * Minimal CSV helpers for preview_slug_map (pdf_path ↔ preview_public_slug).
 */

export function csvEscape(field: string): string {
  if (field.includes('"')) {
    field = field.replace(/"/g, '""');
  }
  if (/[,"\r\n]/.test(field)) {
    return `"${field}"`;
  }
  return field;
}

/** Parse one CSV row; supports quoted fields and doubled quotes. */
export function parseCsvRow(line: string): string[] {
  const fields: string[] = [];
  let cur = "";
  let i = 0;
  let inQuotes = false;

  while (i < line.length) {
    const c = line[i]!;
    if (inQuotes) {
      if (c === '"' && line[i + 1] === '"') {
        cur += '"';
        i += 2;
        continue;
      }
      if (c === '"') {
        inQuotes = false;
        i++;
        continue;
      }
      cur += c;
      i++;
      continue;
    }
    if (c === '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (c === ",") {
      fields.push(cur);
      cur = "";
      i++;
      continue;
    }
    cur += c;
    i++;
  }
  fields.push(cur);
  return fields;
}

function normHeader(h: string): string {
  return h.trim().toLowerCase();
}

/** Reads pdf_path / preview_public_slug columns into a Map. */
export function parseSlugMapCsv(content: string): Map<string, string> {
  const lines = content.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length < 2) {
    throw new Error("CSV must have header + at least one data row.");
  }

  const header = parseCsvRow(lines[0]!);
  const idxPdf = header.findIndex((h) => normHeader(h) === "pdf_path");
  const idxSlug = header.findIndex((h) => normHeader(h) === "preview_public_slug");
  if (idxPdf < 0 || idxSlug < 0) {
    throw new Error(
      `CSV must define columns pdf_path and preview_public_slug (got: ${header.join(", ")})`,
    );
  }

  const map = new Map<string, string>();
  for (let r = 1; r < lines.length; r++) {
    const row = parseCsvRow(lines[r]!);
    const pdfRaw = row[idxPdf]?.trim();
    const slugRaw = row[idxSlug]?.trim();
    if (!pdfRaw || !slugRaw) continue;
    const pdf = pdfRaw.replace(/\\/g, "/");
    map.set(pdf, slugRaw);
  }
  return map;
}
