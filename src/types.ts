// src/types.ts

// ─── OpenLibrary API response types ──────────────────────────────────────────

/**
 * Shape of a single document returned by the Search API.
 * Only fields explicitly requested via the `fields=` parameter are present.
 * Does NOT include work-detail fields like description or first_sentence —
 * those come from the Works API and live in OpenLibraryWorkDetail below.
 */
export interface OpenLibrarySearchResult {
  key: string;                  // e.g. "/works/OL27448W"
  title: string;
  author_name?: string[];
  author_key?: string[];        // e.g. ["OL26320A"] — used for author image lookup
  first_publish_year?: number;
  cover_i?: number;             // Cover ID, used to build Covers API URL
  edition_count?: number;
  isbn?: string[];
  language?: string[];
  publisher?: string[];
}

/**
 * Top-level shape of the Search API response.
 * Note: the API returns both numFound and num_found for backward compatibility.
 */
export interface OpenLibrarySearchResponse {
  numFound: number;
  num_found?: number;           // legacy alias, both present in real responses
  start: number;
  numFoundExact: boolean;
  docs: OpenLibrarySearchResult[];
}

/**
 * Shape of the Works API response (/works/{key}.json).
 * Fetched after the user selects a work from the picker, before note creation.
 * These fields are NOT available from the Search API.
 */
export interface OpenLibraryWorkDetail {
  key: string;
  title: string;
  // Description may be a plain string or an object with a value property
  description?: string | { value: string };
  first_sentence?: string | { value: string };
  subjects?: string[];
  subject_places?: string[];
  subject_times?: string[];
  // Authors are referenced by key in work detail, not returned inline
  authors?: Array<{ author: { key: string } }>;
}

// ─── Cover size ───────────────────────────────────────────────────────────────

export type CoverSize = 'S' | 'M' | 'L';
export type CoverKeyType = 'isbn' | 'olid' | 'id' | 'oclc' | 'lccn';

// ─── Normalised internal Book type ───────────────────────────────────────────

/**
 * Normalised representation used throughout the plugin.
 * Populated from OpenLibrarySearchResult for the picker,
 * then enriched from OpenLibraryWorkDetail before note creation.
 */
export interface Book {
  // From search result
  olid: string;                 // Work key without the /works/ prefix, e.g. "OL27448W"
  title: string;
  author: string;               // First author name, normalised to a single string
  authorKey?: string;           // First author key, for future author image lookup
  publishYear?: number;
  coverId?: number;
  editionCount?: number;
  isbn10?: string;
  isbn13?: string;
  language?: string;

  // Enriched from work detail (populated after picker selection)
  description?: string;
  firstSentence?: string;
  subjects?: string[];
  publisher?: string;
}

// ─── Import / batch workflow types ───────────────────────────────────────────

/**
 * Status of a single book entry during bulk import.
 *
 * clean        — exactly one high-confidence result, ready to create note
 * needs_review — multiple candidates returned, user must pick
 * not_found    — zero results from OpenLibrary
 * error        — network or parse failure
 */
export type ImportStatus = 'clean' | 'needs_review' | 'not_found' | 'error';

export interface BookImportResult {
  inputTitle: string;
  inputAuthor?: string;
  status: ImportStatus;
  candidates?: Book[];          // present when status is 'needs_review'
  selected?: Book;              // present when status is 'clean'
  errorMessage?: string;        // present when status is 'error'
}

// ─── Provider and network client interfaces ───────────────────────────────────

export interface IBookProvider {
  /** General-purpose Solr query — useful for ISBN, subject, or freeform searches */
  search(query: string): Promise<Book[]>;

  /** Title-scoped search with optional author disambiguation */
  searchByTitle(title: string, author?: string): Promise<Book[]>;
}

export interface INetworkClient {
  get<T>(url: string, headers?: Record<string, string>): Promise<T>;
}

// ─── Plugin settings ──────────────────────────────────────────────────────────

export interface PluginSettings {
  /** Optional — when set, sent as User-Agent contact for 3x rate limit */
  userEmail?: string;
  /** Path to the template file used when creating book notes */
  templatePath: string;
  /** Vault folder where book notes are created */
  folderPath: string;
}
