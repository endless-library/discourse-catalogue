// Pure data helpers for the catalogue (no Ember imports, so they can be unit tested).

// Cover images of exactly this size are Google Books' "image not available" placeholder.
const PLACEHOLDER_COVER_SIZE = 15567;

const str = (v) => (v === null || v === undefined ? "" : String(v));

// "A, B, C" -> all tags; the last one is the book's current collection,
// earlier ones are collections it was previously filed under.
export function parseTags(raw) {
  const parts = str(raw)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return {
    all: parts,
    active: parts.length ? parts[parts.length - 1] : null,
    historical: parts.slice(0, -1),
  };
}

function bookKey(title, author) {
  return `${str(title).trim().toLowerCase()}|${str(author).trim().toLowerCase()}`;
}

function isbnDigits(isbn) {
  return str(isbn).replace(/[^0-9X]/gi, "").toUpperCase();
}

// Turns the raw JSON from Apps Script into the shapes the UI uses, with
// search text and cover flags precomputed once rather than on every keystroke.
export function prepareCatalogue(data) {
  const books = (data?.books || [])
    .filter((b) => b && str(b.title).trim())
    .map((b) => {
      const tags = parseTags(b.tags);
      const book = {
        title: str(b.title).trim(),
        author: str(b.author).trim(),
        year: str(b.year).trim(),
        genre: str(b.genre).trim(),
        isbn: str(b.isbn).trim(),
        collection: str(b.collection).trim(),
        tags: str(b.tags).trim(),
        publisher: str(b.publisher).trim(),
        format: str(b.format).trim(),
        language: str(b.language).trim(),
        callNumber: str(b.callNumber).trim(),
        coverUrl: str(b.coverUrl).trim(),
      };
      const coverSize = Number(b.coverSize) || 0;
      book._tags = tags.all;
      book._activeTag = tags.active;
      book._tagKeys = tags.all.map((t) => t.toLowerCase());
      book._hasCover =
        !!book.coverUrl && coverSize > 0 && coverSize !== PLACEHOLDER_COVER_SIZE;
      book._fav = Number(b.favourite) || 0;
      book._year = book.year.slice(0, 4);
      book._isbn = isbnDigits(book.isbn);
      book._haystack = [
        book.title,
        book.author,
        book.genre,
        book.isbn,
        book.collection,
        book.tags,
        book.publisher,
      ]
        .join(" \u0001 ")
        .toLowerCase();
      return book;
    });

  const byKey = new Map();
  for (const b of books) {
    if (b._isbn && !byKey.has(`isbn:${b._isbn}`)) {
      byKey.set(`isbn:${b._isbn}`, b);
    }
    const k = bookKey(b.title, b.author);
    if (!byKey.has(k)) {
      byKey.set(k, b);
    }
  }

  const tagNames = new Map();
  for (const b of books) {
    for (const t of b._tags) {
      const k = t.toLowerCase();
      if (!tagNames.has(k)) {
        tagNames.set(k, t);
      }
    }
  }
  const tagOptions = [...tagNames]
    .sort((a, b) => a[1].localeCompare(b[1]))
    .map(([key, name]) => ({ key, name }));

  const collections = (data?.collections || []).map((c) => {
    const active = (c.active || []).map((x) => ({
      title: str(x.Title).trim(),
      author: str(x.Author).trim(),
      isbn: str(x.ISBN13).trim(),
      refOnly: !!x._refOnly,
    }));
    const historical = (c.historical || []).map((x) => ({
      title: str(x.Title).trim(),
      author: str(x.Author).trim(),
      isbn: str(x.ISBN13).trim(),
      refOnly: !!x._refOnly,
    }));
    const count = Number.isFinite(c.activeCount) ? c.activeCount : active.length;
    return {
      name: str(c.name),
      active,
      historical,
      countLabel: `${count} book${count === 1 ? "" : "s"}`,
      preview:
        active
          .slice(0, 3)
          .map((x) => x.title)
          .join(", ") + (active.length > 3 ? "…" : ""),
      _search: [c.name, ...active.map((x) => `${x.title} ${x.author}`)]
        .join(" ")
        .toLowerCase(),
    };
  });

  return { books, collections, tagOptions, byKey };
}

// Finds the full record for a book listed in a collection (matched by ISBN,
// then title + author). Returns null for reference-only books, which the
// public feed leaves out.
export function findBook(byKey, entry) {
  if (!byKey || !entry) {
    return null;
  }
  const digits = isbnDigits(entry.isbn);
  return (
    (digits && byKey.get(`isbn:${digits}`)) ||
    byKey.get(bookKey(entry.title, entry.author)) ||
    null
  );
}

// filters: { query, title, author, genre, isbn, year, tag }
export function filterBooks(books, filters) {
  let r = books || [];
  const q = str(filters.query).trim().toLowerCase();
  if (q) {
    const terms = q.split(/\s+/);
    r = r.filter((b) => terms.every((t) => b._haystack.includes(t)));
  }
  const field = (name, prop) => {
    const v = str(filters[name]).trim().toLowerCase();
    if (v) {
      r = r.filter((b) => b[prop].toLowerCase().includes(v));
    }
  };
  field("title", "title");
  field("author", "author");
  field("genre", "genre");
  const isbn = isbnDigits(filters.isbn);
  if (isbn) {
    r = r.filter((b) => b._isbn.includes(isbn));
  }
  const year = str(filters.year).trim();
  if (year) {
    r = r.filter((b) => b.year.startsWith(year));
  }
  const tag = str(filters.tag).trim().toLowerCase();
  if (tag) {
    r = r.filter((b) => b._tagKeys.includes(tag));
  }
  return r;
}

// Sorts by a field; blanks always go last. In covers mode, favourites come
// first (in favourite order), then books with real covers, then the rest.
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

export function orderBooks(books, { field = "title", asc = true, covers = false }) {
  const prop = field === "year" ? "_year" : field;
  const sorted = [...books].sort((a, b) => {
    const va = a[prop] || "";
    const vb = b[prop] || "";
    if (!va !== !vb) {
      return va ? -1 : 1;
    }
    const r = collator.compare(va, vb);
    return asc ? r : -r;
  });
  if (!covers) {
    return sorted;
  }
  const favourites = sorted.filter((b) => b._fav > 0).sort((a, b) => a._fav - b._fav);
  const withCover = sorted.filter((b) => b._fav <= 0 && b._hasCover);
  const rest = sorted.filter((b) => b._fav <= 0 && !b._hasCover);
  return [...favourites, ...withCover, ...rest];
}

// Drive thumbnails take a size parameter; ask for a larger one in the detail view.
export function largeCover(url) {
  return str(url).replace(/([?&]sz=w)\d+/, "$1600");
}
