import { tracked } from "@glimmer/tracking";
import { findBook, prepareCatalogue } from "./catalogue-data";

// One shared store for the whole app, so the header links and the catalogue
// page agree on which view is showing, and the data is only downloaded once
// per visit.
//
// Loading strategy (stale-while-revalidate): the last copy a visitor
// downloaded is kept in localStorage and shown instantly; a fresh copy is
// fetched in the background when that copy is older than the configured age.

const META_KEY = "el-catalogue:meta";
const DATA_KEY = "el-catalogue:data";

function readLocal(key) {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeLocal(key, value) {
  try {
    window.localStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

class CatalogueStore {
  @tracked view = "books";
  @tracked books = null;
  @tracked collections = [];
  @tracked tagOptions = [];
  @tracked error = null;
  @tracked loading = false;

  byKey = null;
  fetchedAt = 0;
  rawText = null;
  inflight = null;

  setView(view) {
    if (view === "books" || view === "collections") {
      this.view = view;
    }
  }

  findBook(entry) {
    return findBook(this.byKey, entry);
  }

  ensureLoaded(url, maxAgeMinutes) {
    if (!url) {
      this.error = "No catalogue data URL is set in the theme settings.";
      return;
    }
    if (!this.books) {
      this.readCache(url);
    }
    const maxAge = Math.max(0, Number(maxAgeMinutes) || 0) * 60 * 1000;
    const stale = Date.now() - this.fetchedAt >= maxAge;
    if ((!this.books || stale) && !this.inflight) {
      this.inflight = this.fetchFresh(url);
    }
  }

  retry(url) {
    this.error = null;
    this.fetchedAt = 0;
    this.ensureLoaded(url, 0);
  }

  readCache(url) {
    const meta = readLocal(META_KEY);
    const text = readLocal(DATA_KEY);
    if (!meta || !text) {
      return;
    }
    try {
      const { t, source } = JSON.parse(meta);
      if (source !== url) {
        return; // data URL changed in settings; ignore the old copy
      }
      this.apply(text, Number(t) || 0);
    } catch {
      // corrupt cache: ignore it, a fresh copy is about to be fetched
    }
  }

  async fetchFresh(url) {
    this.loading = !this.books;
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`The catalogue server answered with HTTP ${response.status}.`);
      }
      const text = await response.text();
      const now = Date.now();
      if (text !== this.rawText) {
        this.apply(text, now);
      } else {
        this.fetchedAt = now;
      }
      if (writeLocal(DATA_KEY, text)) {
        writeLocal(META_KEY, JSON.stringify({ t: now, source: url }));
      }
      this.error = null;
    } catch (e) {
      // Keep showing the cached copy if there is one; only surface the error
      // when there is nothing to show.
      // eslint-disable-next-line no-console
      console.error("[catalogue] could not refresh the catalogue", e);
      if (!this.books) {
        this.error =
          e instanceof SyntaxError
            ? "The catalogue server sent something that isn't catalogue data."
            : e.message || String(e);
      }
    } finally {
      this.loading = false;
      this.inflight = null;
    }
  }

  apply(text, fetchedAt) {
    const data = JSON.parse(text);
    if (!data || !Array.isArray(data.books)) {
      throw new SyntaxError("Unexpected catalogue response");
    }
    const prepared = prepareCatalogue(data);
    this.byKey = prepared.byKey;
    this.collections = prepared.collections;
    this.tagOptions = prepared.tagOptions;
    this.books = prepared.books;
    this.rawText = text;
    this.fetchedAt = fetchedAt;
  }
}

export default new CatalogueStore();

export function catalogueUrl(slug) {
  return `/c/${slug}`;
}

export function isCatalogueCategory(category, slug) {
  return !!category && !!slug && category.slug === slug;
}
