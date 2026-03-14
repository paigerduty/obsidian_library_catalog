#!/usr/bin/env npx tsx
// scripts/test-import.ts
//
// Standalone script — no Obsidian, no plugin build required.
// Run from workspace root: npx tsx scripts/test-import.ts
//
// What it does:
//   1. Runs every title in BOOKS through OpenLibrary's Search API via the real
//      OpenLibraryProvider (same code the plugin uses at runtime).
//   2. Classifies each result as clean | needs_review | not_found | error.
//   3. Streams live progress to the terminal as each book resolves.
//   4. Prints a summary of counts per status bucket.
//   5. Writes scripts/import-report.json with the full BookImportResult[].
//
// Classification logic:
//   clean        — top result title is an exact case-insensitive match to input title
//   needs_review — results returned but none is an exact title match
//   not_found    — zero results
//   error        — network or parse failure

import { readFile, writeFile } from "fs/promises";
import { resolve } from "path";
import { OpenLibraryProvider } from "../src/provider";
import { Book, BookImportResult, ImportStatus } from "../src/types";
import { INetworkClient } from "../src/types";

class NodeHttpClient implements INetworkClient {
  async get<T>(url: string, headers?: Record<string, string>): Promise<T> {
    const res = await fetch(url, { headers });
    if (!res.ok) throw new Error(`HTTP ${res.status} — ${url}`);
    return res.json() as Promise<T>;
  }
}

// ─── Book list ────────────────────────────────────────────────────────────────
// Sample list used when no input file is provided.
// Pass a JSON file as a CLI argument to run your full list:
//   npx tsx scripts/test-import.ts books.json

type BookEntry = { title: string; author?: string };

const SAMPLE_BOOKS: BookEntry[] = [
  { title: "The Intentional Spinner", author: "Judith MacKenzie McCuin" },
  { title: "No Sheep For You", author: "Amy R. Singer" },
  { title: "Knitlandia", author: "Clara Parkes" },
  { title: "Fibershed", author: "Rebecca Burgess" },
  { title: "Principles of Color", author: "Faber Birren" },
];

async function loadBooks(filePath?: string): Promise<BookEntry[]> {
  if (!filePath) {
    console.log("   No input file provided — using built-in sample list.\n   To use your own: npx tsx scripts/test-import.ts books.json\n");
    return SAMPLE_BOOKS;
  }

  const absPath = resolve(process.cwd(), filePath);
  let raw: string;
  try {
    raw = await readFile(absPath, "utf8");
  } catch {
    console.error(`❌ Could not read file: ${absPath}`);
    console.error(`   Make sure the path is correct and the file exists.`);
    process.exit(1);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    console.error(`❌ Could not parse JSON from: ${absPath}`);
    console.error(`   Expected format: [{ "title": "...", "author": "..." }, ...]`);
    process.exit(1);
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    console.error(`❌ Input file must be a non-empty JSON array: ${absPath}`);
    process.exit(1);
  }

  // Validate each entry has at least a title string
  const books: BookEntry[] = [];
  for (const [i, entry] of parsed.entries()) {
    if (typeof entry !== "object" || entry === null || typeof (entry as Record<string, unknown>).title !== "string") {
      console.error(`❌ Entry at index ${i} is missing a "title" string field.`);
      process.exit(1);
    }
    const e = entry as Record<string, unknown>;
    books.push({
      title: e.title as string,
      ...(typeof e.author === "string" ? { author: e.author } : {}),
    });
  }

  console.log(`   Loaded ${books.length} books from ${absPath}\n`);
  return books;
}

// ─── Classification ───────────────────────────────────────────────────────────

function normalizeTitle(t: string): string {
  return t.toLowerCase().replace(/[^a-z0-9\s]/g, "").trim();
}

function classify(
  inputTitle: string,
  books: Book[]
): { status: ImportStatus; selected?: Book; candidates?: Book[] } {
  if (books.length === 0) return { status: "not_found" };

  const needle = normalizeTitle(inputTitle);
  const exactMatch = books.find(
    (b) => normalizeTitle(b.title) === needle
  );

  if (exactMatch) {
    return { status: "clean", selected: exactMatch };
  }

  return { status: "needs_review", candidates: books };
}

// ─── Terminal formatting helpers ──────────────────────────────────────────────

const STATUS_ICONS: Record<ImportStatus, string> = {
  clean: "✅",
  needs_review: "🔍",
  not_found: "❌",
  error: "💥",
};

const TITLE_COL = 52;
const STATUS_COL = 15;

/** Pad or truncate a string to exactly `len` visible characters. */
function col(s: string, len: number): string {
  if (s.length > len) return s.slice(0, len - 1) + "…";
  return s + " ".repeat(len - s.length);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const client = new NodeHttpClient();
  const USER_EMAIL = process.env.OPENLIBRARY_EMAIL ?? undefined;
  const provider = new OpenLibraryProvider(client, USER_EMAIL);

  const inputFile = process.argv[2]; // e.g. "books.json" or undefined
  const books = await loadBooks(inputFile);

  console.log("\n📚 OpenLibrary Import Test");
  console.log(`   ${books.length} books · ${USER_EMAIL ? `identified as ${USER_EMAIL}` : "anonymous (1 req/s)"}\n`);
  console.log(
    col("Title", TITLE_COL) + "│ " + col("Status", STATUS_COL) + "│ Top result"
  );
  console.log("─".repeat(TITLE_COL) + "┼─" + "─".repeat(STATUS_COL) + "┼─" + "─".repeat(30));

  const results: BookImportResult[] = [];

  for (const { title, author } of books) {
    let result: BookImportResult;

    try {
      const books = await provider.searchByTitle(title, author);
      const { status, selected, candidates } = classify(title, books);

      const topResultTitle =
        selected?.title ?? candidates?.[0]?.title ?? "—";

      result = {
        inputTitle: title,
        inputAuthor: author,
        status,
        ...(selected ? { selected } : {}),
        ...(candidates ? { candidates } : {}),
      };

      console.log(
        col(title, TITLE_COL) + "│ " +
        col(`${STATUS_ICONS[status]} ${status}`, STATUS_COL) + "│ " +
        topResultTitle
      );
    } catch (err) {
      const errorMessage =
        err instanceof Error ? err.message : String(err);

      result = {
        inputTitle: title,
        inputAuthor: author,
        status: "error",
        errorMessage,
      };

      console.log(
        col(title, TITLE_COL) + "│ " +
        col(`${STATUS_ICONS.error} error`, STATUS_COL) + "│ " +
        errorMessage
      );
    }

    results.push(result);
  }

  // ─── Summary ──────────────────────────────────────────────────────────────

  const counts: Record<ImportStatus, number> = {
    clean: 0,
    needs_review: 0,
    not_found: 0,
    error: 0,
  };
  for (const r of results) counts[r.status]++;

  console.log("\n" + "─".repeat(TITLE_COL + STATUS_COL + 34));
  console.log("Summary");
  console.log(`  ✅ clean:        ${counts.clean}`);
  console.log(`  🔍 needs_review: ${counts.needs_review}`);
  console.log(`  ❌ not_found:    ${counts.not_found}`);
  console.log(`  💥 error:        ${counts.error}`);
  console.log(`  📦 total:        ${books.length}`);

  // ─── Write report ─────────────────────────────────────────────────────────

  const reportPath = resolve(process.cwd(), "scripts", "import-report.json");
  await writeFile(reportPath, JSON.stringify(results, null, 2), "utf8");
  console.log(`\n📄 Full report written to: ${reportPath}\n`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
