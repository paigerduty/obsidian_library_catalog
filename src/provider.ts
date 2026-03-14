// src/provider.ts
import {
  IBookProvider,
  INetworkClient,
  OpenLibrarySearchResponse,
  Book,
} from "./types";
import { mapOpenLibrarySearchResult } from "./mapper";

// ─── Constants ────────────────────────────────────────────────────────────────

const BASE_URL = "https://openlibrary.org";

/**
 * Explicit field list for search requests.
 * Only request what the picker and note template actually need.
 * Keeps responses small and shapes predictable — per OpenLibrary usage guidelines.
 */
const SEARCH_FIELDS = [
  "key",
  "title",
  "author_name",
  "author_key",
  "first_publish_year",
  "cover_i",
  "edition_count",
  "isbn",
  "publisher",
  "language",
].join(",");

/** Conservative result limit for picker — enough to show meaningful options */
const DEFAULT_LIMIT = 5;

// ─── Rate limiter ─────────────────────────────────────────────────────────────

class RateLimiter {
  private timestamps: number[] = [];
  private readonly WINDOW_MS = 1000; // 1 second sliding window

  constructor(private maxRequests: number) {}

  async acquire(): Promise<void> {
    const now = Date.now();

    // Evict timestamps outside the current window
    while (
      this.timestamps.length > 0 &&
      this.timestamps[0]! <= now - this.WINDOW_MS
    ) {
      this.timestamps.shift();
    }

    // If at the limit, wait until the oldest timestamp falls outside the window
    if (this.timestamps.length >= this.maxRequests) {
      const waitTime = this.timestamps[0]! + this.WINDOW_MS - now;
      await new Promise((resolve) => setTimeout(resolve, waitTime));
    }

    this.timestamps.push(Date.now());
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

export class OpenLibraryProvider implements IBookProvider {
  private rateLimiter: RateLimiter;

  constructor(
    private client: INetworkClient,
    private userEmail?: string
  ) {
    this.rateLimiter = new RateLimiter(userEmail ? 3 : 1);
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /**
   * General-purpose Solr query search.
   * Useful for ISBN lookup, subject search, or any freeform query.
   * Example: search('isbn:9780385533225')
   */
  async search(query: string): Promise<Book[]> {
    const params = new URLSearchParams({
      q: query,
      fields: SEARCH_FIELDS,
      limit: String(DEFAULT_LIMIT),
    });
    return this.executeSearch(params);
  }

  /**
   * Title-scoped search with optional author disambiguation.
   * Preferred over search() for the book picker flow — scoping to the title
   * field significantly reduces noise for common or short titles.
   */
  async searchByTitle(title: string, author?: string): Promise<Book[]> {
    const params = new URLSearchParams({
      title,
      fields: SEARCH_FIELDS,
      limit: String(DEFAULT_LIMIT),
    });
    if (author) {
      params.set("author", author);
    }
    return this.executeSearch(params);
  }

  /**
   * Update user email and reset rate limiter.
   * Called when the user adds or removes their email in plugin settings.
   */
  updateUserEmail(userEmail?: string): void {
    this.userEmail = userEmail;
    this.rateLimiter = new RateLimiter(userEmail ? 3 : 1);
  }

  // ─── Private helpers ─────────────────────────────────────────────────────────

  private buildHeaders(): Record<string, string> {
    const appName = "obsidian-library-catalog";
    return {
      "User-Agent": this.userEmail
        ? `${appName} (${this.userEmail})`
        : appName,
    };
  }

  private async executeSearch(params: URLSearchParams): Promise<Book[]> {
    await this.rateLimiter.acquire();

    const url = `${BASE_URL}/search.json?${params.toString()}`;
    const headers = this.buildHeaders();

    try {
      const response = await this.client.get<OpenLibrarySearchResponse>(
        url,
        headers
      );

      if (!response.docs || response.docs.length === 0) {
        return [];
      }

      return response.docs.map(mapOpenLibrarySearchResult);
    } catch (error) {
      if (error instanceof Error) {
        if (error.message.includes("429")) {
          throw new Error(
            "Rate limit exceeded. Please wait before making more requests."
          );
        }
        throw new Error(`Failed to search OpenLibrary: ${error.message}`);
      }
      throw new Error("Failed to search OpenLibrary: Unknown error");
    }
  }
}
