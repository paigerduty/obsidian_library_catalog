// src/mapper.ts
import { OpenLibrarySearchResult, OpenLibraryWorkDetail, Book } from "./types";

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * OpenLibrary returns some text fields as either a plain string or an object
 * with a `value` property. This normalises both shapes to a plain string.
 */
function extractText(
  field: string | { value: string } | undefined
): string | undefined {
  if (!field) return undefined;
  if (typeof field === "string") return field;
  return field.value;
}

/**
 * Strips the "/works/" path prefix from a work key.
 * "/works/OL27448W" → "OL27448W"
 */
function extractOlid(key: string): string {
  return key.replace(/^\/works\//, "");
}

function extractIsbn(isbns: string[] | undefined, length: 10 | 13): string | undefined {
  return isbns?.find((isbn) => isbn.length === length);
}

// ─── Search result → Book (picker data) ──────────────────────────────────────

/**
 * Maps a raw Search API document to a Book.
 * Only fields available from the Search API are populated here.
 * Description, firstSentence, and subjects remain undefined until
 * enrichBookWithWorkDetail() is called after the user makes their selection.
 */
export function mapOpenLibrarySearchResult(raw: OpenLibrarySearchResult): Book {
  return {
    olid: extractOlid(raw.key),
    title: raw.title,
    author: raw.author_name?.[0] ?? "Unknown Author",
    authorKey: raw.author_key?.[0],
    publishYear: raw.first_publish_year,
    coverId: raw.cover_i,
    editionCount: raw.edition_count,
    isbn10: extractIsbn(raw.isbn, 10),
    isbn13: extractIsbn(raw.isbn, 13),
    language: raw.language?.[0],
    publisher: raw.publisher?.[0],
    // description, firstSentence, subjects populated later via enrichBookWithWorkDetail
  };
}

// ─── Work detail → Book enrichment (post-picker) ─────────────────────────────

/**
 * Merges work detail fields into an existing Book after the user has selected
 * a result from the picker. Returns a new object — does not mutate the input.
 */
export function enrichBookWithWorkDetail(
  book: Book,
  detail: OpenLibraryWorkDetail
): Book {
  return {
    ...book,
    description: extractText(detail.description),
    firstSentence: extractText(detail.first_sentence),
    subjects: detail.subjects,
  };
}
