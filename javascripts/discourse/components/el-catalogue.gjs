import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { filterBooks, orderBooks } from "../lib/catalogue-data";
import store from "../lib/catalogue-store";
import ElBookModal from "./el-book-modal";

const COVER_STEP = 60;
const LIST_STEP = 150;
const SKELETON = Array.from({ length: 12 });

const isEq = (a, b) => a === b;

// Calls `callback` when the element scrolls near the viewport (infinite
// scroll). The second argument (the current limit) re-arms the observer after
// each batch, so a tall screen keeps loading until it is full.
// eslint-disable-next-line no-unused-vars
const nearViewport = modifier((element, [callback, _limit]) => {
  if (!("IntersectionObserver" in window)) {
    return;
  }
  const observer = new IntersectionObserver(
    (entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        callback();
      }
    },
    { rootMargin: "800px 0px" }
  );
  observer.observe(element);
  return () => observer.disconnect();
});

export default class ElCatalogue extends Component {
  @service modal;

  @tracked query = "";
  @tracked advOpen = false;
  @tracked advTitle = "";
  @tracked advAuthor = "";
  @tracked advGenre = "";
  @tracked advIsbn = "";
  @tracked advYear = "";
  @tracked advTag = "";
  @tracked mode = "covers";
  @tracked sortField = "title";
  @tracked sortAsc = true;
  @tracked limit = COVER_STEP;
  @tracked collectionFilter = "";
  @tracked openCollections = new Set();

  // true when a search switched covers -> list for us, so clearing it can switch back
  autoListed = false;

  store = store;
  skeleton = SKELETON;

  constructor() {
    super(...arguments);
    store.ensureLoaded(settings.data_url, settings.refresh_after_minutes);
  }

  get booksLabel() {
    return settings.books_label;
  }

  get collectionsLabel() {
    return settings.collections_label;
  }

  // When the header shows Browse books / Browse collections, the page's own
  // tabs are hidden on wider screens (CSS); phones keep them, because the
  // header there only has room for a single Catalogue link.
  get rootClass() {
    return settings.show_header_links
      ? "el-catalogue el-catalogue--header-nav"
      : "el-catalogue";
  }

  get isBooks() {
    return store.view !== "collections";
  }

  get isCovers() {
    return this.mode === "covers";
  }

  get advCount() {
    return [
      this.advTitle,
      this.advAuthor,
      this.advGenre,
      this.advIsbn,
      this.advYear,
      this.advTag,
    ].filter((v) => v.trim()).length;
  }

  get hasFilters() {
    return !!this.query.trim() || this.advCount > 0;
  }

  @cached
  get filtered() {
    return filterBooks(store.books, {
      query: this.query,
      title: this.advTitle,
      author: this.advAuthor,
      genre: this.advGenre,
      isbn: this.advIsbn,
      year: this.advYear,
      tag: this.advTag,
    });
  }

  @cached
  get ordered() {
    return orderBooks(this.filtered, {
      field: this.sortField,
      asc: this.sortAsc,
      covers: this.isCovers,
    });
  }

  get visible() {
    return this.ordered.slice(0, this.limit);
  }

  get hasMore() {
    return this.ordered.length > this.limit;
  }

  get resultsMeta() {
    if (!store.books) {
      return "";
    }
    const total = store.books.length.toLocaleString();
    if (!this.hasFilters) {
      return `${total} books`;
    }
    const n = this.filtered.length;
    return `${n.toLocaleString()} of ${total} books`;
  }

  get activeTagName() {
    return store.tagOptions.find((t) => t.key === this.advTag)?.name;
  }

  @cached
  get collections() {
    const f = this.collectionFilter.trim().toLowerCase();
    const list = store.collections || [];
    return f ? list.filter((c) => c._search.includes(f)) : list;
  }

  sortIndicator = (field) =>
    this.sortField === field ? (this.sortAsc ? "▲" : "▼") : "";

  ariaSort = (field) =>
    this.sortField === field ? (this.sortAsc ? "ascending" : "descending") : "none";

  isCollectionOpen = (name) => this.openCollections.has(name);

  resetLimit() {
    this.limit = this.isCovers ? COVER_STEP : LIST_STEP;
  }

  @action
  setView(view) {
    store.setView(view);
  }

  @action
  onQuery(event) {
    const value = event.target.value;
    const had = !!this.query.trim();
    const has = !!value.trim();
    this.query = value;
    // Searching shows a list, which is easier to scan than covers.
    if (has && !had && this.isCovers) {
      this.mode = "list";
      this.autoListed = true;
    } else if (!has && had && this.autoListed && this.advCount === 0) {
      this.mode = "covers";
      this.autoListed = false;
    }
    this.resetLimit();
  }

  @action
  onQueryKeydown(event) {
    if (event.key === "Escape" && this.query) {
      event.preventDefault();
      this.clearQuery();
    }
  }

  @action
  clearQuery() {
    this.onQuery({ target: { value: "" } });
  }

  @action
  setAdv(field, event) {
    this[field] = event.target.value;
    this.resetLimit();
  }

  @action
  toggleAdv() {
    this.advOpen = !this.advOpen;
  }

  @action
  clearAdv() {
    this.advTitle = "";
    this.advAuthor = "";
    this.advGenre = "";
    this.advIsbn = "";
    this.advYear = "";
    this.advTag = "";
    if (this.autoListed && !this.query.trim()) {
      this.mode = "covers";
      this.autoListed = false;
    }
    this.resetLimit();
  }

  @action
  setMode(mode) {
    this.mode = mode;
    this.autoListed = false;
    this.resetLimit();
  }

  @action
  sortBy(field) {
    if (this.sortField === field) {
      this.sortAsc = !this.sortAsc;
    } else {
      this.sortField = field;
      this.sortAsc = true;
    }
    this.resetLimit();
  }

  @action
  showMore() {
    this.limit += this.isCovers ? COVER_STEP : LIST_STEP;
  }

  @action
  openBook(book) {
    this.modal.show(ElBookModal, {
      model: { book, onTag: this.filterByTag },
    });
  }

  @action
  filterByTag(name) {
    store.setView("books");
    this.query = "";
    this.advTitle = "";
    this.advAuthor = "";
    this.advGenre = "";
    this.advIsbn = "";
    this.advYear = "";
    this.advTag = String(name).toLowerCase();
    this.advOpen = true;
    this.mode = "covers";
    this.autoListed = false;
    this.resetLimit();
    window.scrollTo({ top: 0 });
  }

  @action
  coverError(event) {
    event.target.closest(".el-cover__img")?.classList.add("is-broken");
  }

  @action
  retry() {
    store.retry(settings.data_url);
  }

  @action
  onCollectionFilter(event) {
    this.collectionFilter = event.target.value;
  }

  @action
  toggleCollection(name) {
    const next = new Set(this.openCollections);
    if (next.has(name)) {
      next.delete(name);
    } else {
      next.add(name);
    }
    this.openCollections = next;
  }

  @action
  openCollectionBook(entry) {
    const book = store.findBook(entry);
    this.openBook(
      book || {
        title: entry.title,
        author: entry.author,
        isbn: entry.isbn,
        _tags: [],
        _hasCover: false,
        _referenceOnly: entry.refOnly,
      }
    );
  }

  <template>
    <section class={{this.rootClass}} aria-labelledby="el-catalogue-heading">
      <h1 id="el-catalogue-heading" class="sr-only">Library catalogue</h1>

      <div class="el-tabs" role="tablist" aria-label="Catalogue views">
        <button
          type="button"
          role="tab"
          class="el-tab {{if this.isBooks 'is-active'}}"
          aria-selected={{if this.isBooks "true" "false"}}
          {{on "click" (fn this.setView "books")}}
        >{{this.booksLabel}}</button>
        <button
          type="button"
          role="tab"
          class="el-tab {{unless this.isBooks 'is-active'}}"
          aria-selected={{if this.isBooks "false" "true"}}
          {{on "click" (fn this.setView "collections")}}
        >{{this.collectionsLabel}}</button>
      </div>

      {{#if this.store.books}}
        {{#if this.isBooks}}
          <div class="el-search">
            <div class="el-search__bar">
              <input
                type="search"
                class="el-search__input"
                placeholder="Search by title, author, genre, ISBN…"
                aria-label="Search the catalogue"
                autocomplete="off"
                value={{this.query}}
                {{on "input" this.onQuery}}
                {{on "keydown" this.onQueryKeydown}}
              />
              {{#if this.query}}
                <button
                  type="button"
                  class="el-search__clear"
                  aria-label="Clear search"
                  {{on "click" this.clearQuery}}
                >✕</button>
              {{/if}}
            </div>

            <button
              type="button"
              class="el-adv-toggle {{if this.advOpen 'is-open'}}"
              aria-expanded={{if this.advOpen "true" "false"}}
              aria-controls="el-adv-panel"
              {{on "click" this.toggleAdv}}
            >
              <span class="el-adv-toggle__arrow" aria-hidden="true">▼</span>
              Advanced search
              {{#if this.advCount}}
                <span class="el-adv-toggle__count">({{this.advCount}})</span>
              {{/if}}
            </button>

            {{#if this.advOpen}}
              <div class="el-adv" id="el-adv-panel">
                <label class="el-adv__field">
                  <span>Title</span>
                  <input
                    type="text"
                    placeholder="e.g. Middlemarch"
                    value={{this.advTitle}}
                    {{on "input" (fn this.setAdv "advTitle")}}
                  />
                </label>
                <label class="el-adv__field">
                  <span>Author</span>
                  <input
                    type="text"
                    placeholder="e.g. George Eliot"
                    value={{this.advAuthor}}
                    {{on "input" (fn this.setAdv "advAuthor")}}
                  />
                </label>
                <label class="el-adv__field">
                  <span>Genre / subject</span>
                  <input
                    type="text"
                    placeholder="e.g. Philosophy"
                    value={{this.advGenre}}
                    {{on "input" (fn this.setAdv "advGenre")}}
                  />
                </label>
                <label class="el-adv__field">
                  <span>ISBN</span>
                  <input
                    type="text"
                    inputmode="numeric"
                    placeholder="e.g. 9780141439563"
                    value={{this.advIsbn}}
                    {{on "input" (fn this.setAdv "advIsbn")}}
                  />
                </label>
                <label class="el-adv__field">
                  <span>Year</span>
                  <input
                    type="text"
                    inputmode="numeric"
                    placeholder="e.g. 2003"
                    value={{this.advYear}}
                    {{on "input" (fn this.setAdv "advYear")}}
                  />
                </label>
                <label class="el-adv__field">
                  <span>Collection / tag</span>
                  <select {{on "change" (fn this.setAdv "advTag")}}>
                    <option value="" selected={{isEq this.advTag ""}}>Any</option>
                    {{#each this.store.tagOptions as |t|}}
                      <option
                        value={{t.key}}
                        selected={{isEq t.key this.advTag}}
                      >{{t.name}}</option>
                    {{/each}}
                  </select>
                </label>
                <div class="el-adv__actions">
                  <button
                    type="button"
                    class="el-btn"
                    {{on "click" this.clearAdv}}
                  >Clear</button>
                </div>
              </div>
            {{/if}}
          </div>

          <div class="el-results-bar">
            <p class="el-results-meta" aria-live="polite">
              {{this.resultsMeta}}
              {{#if this.activeTagName}}
                in
                <em>{{this.activeTagName}}</em>
              {{/if}}
            </p>
            <div class="el-view-toggle" role="group" aria-label="Display">
              <button
                type="button"
                class="el-btn {{if this.isCovers 'is-active'}}"
                aria-pressed={{if this.isCovers "true" "false"}}
                {{on "click" (fn this.setMode "covers")}}
              >Covers</button>
              <button
                type="button"
                class="el-btn {{unless this.isCovers 'is-active'}}"
                aria-pressed={{if this.isCovers "false" "true"}}
                {{on "click" (fn this.setMode "list")}}
              >List</button>
            </div>
          </div>

          {{#if this.filtered.length}}
            {{#if this.isCovers}}
              <ul class="el-covers">
                {{#each this.visible as |b|}}
                  <li>
                    <button
                      type="button"
                      class="el-cover"
                      {{on "click" (fn this.openBook b)}}
                    >
                      <span class="el-cover__img" data-title={{b.title}}>
                        {{#if b._hasCover}}
                          <img
                            src={{b.coverUrl}}
                            alt=""
                            loading="lazy"
                            decoding="async"
                            {{on "error" this.coverError}}
                          />
                        {{/if}}
                      </span>
                      <span class="el-cover__title">{{b.title}}</span>
                      <span class="el-cover__author">{{b.author}}</span>
                    </button>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <table class="el-table">
                <thead>
                  <tr>
                    <th aria-sort={{this.ariaSort "title"}}>
                      <button type="button" {{on "click" (fn this.sortBy "title")}}>
                        Title
                        <span class="el-sort">{{this.sortIndicator "title"}}</span>
                      </button>
                    </th>
                    <th aria-sort={{this.ariaSort "author"}}>
                      <button type="button" {{on "click" (fn this.sortBy "author")}}>
                        Author
                        <span class="el-sort">{{this.sortIndicator "author"}}</span>
                      </button>
                    </th>
                    <th class="el-table__meta" aria-sort={{this.ariaSort "year"}}>
                      <button type="button" {{on "click" (fn this.sortBy "year")}}>
                        Year
                        <span class="el-sort">{{this.sortIndicator "year"}}</span>
                      </button>
                    </th>
                    <th class="el-table__meta">Genre</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.visible as |b|}}
                    <tr {{on "click" (fn this.openBook b)}}>
                      <td>
                        {{! the row's click handler opens the book; this button makes it keyboard reachable }}
                        <button type="button" class="el-table__title">{{b.title}}</button>
                      </td>
                      <td class="el-table__author">{{b.author}}</td>
                      <td class="el-table__meta">{{b._year}}</td>
                      <td class="el-table__meta">{{b.genre}}</td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{/if}}

            {{#if this.hasMore}}
              <div class="el-more" {{nearViewport this.showMore this.limit}}>
                <button type="button" class="el-btn" {{on "click" this.showMore}}>
                  Show more
                </button>
              </div>
            {{/if}}
          {{else}}
            <p class="el-state">No books match that search.</p>
          {{/if}}
        {{else}}
          <div class="el-collections">
            <input
              type="search"
              class="el-collections__filter"
              placeholder="Filter collections, or find which one holds a book…"
              aria-label="Filter collections"
              value={{this.collectionFilter}}
              {{on "input" this.onCollectionFilter}}
            />

            {{#if this.collections.length}}
              <ul class="el-coll-list">
                {{#each this.collections as |c|}}
                  <li class="el-coll {{if (this.isCollectionOpen c.name) 'is-open'}}">
                    <button
                      type="button"
                      class="el-coll__row"
                      aria-expanded={{if (this.isCollectionOpen c.name) "true" "false"}}
                      {{on "click" (fn this.toggleCollection c.name)}}
                    >
                      <span class="el-coll__name">{{c.name}}</span>
                      <span class="el-coll__preview">{{c.preview}}</span>
                      <span class="el-coll__count">{{c.countLabel}}</span>
                    </button>
                    {{#if (this.isCollectionOpen c.name)}}
                      <div class="el-coll__books">
                        {{#each c.active as |entry|}}
                          <button
                            type="button"
                            class="el-coll__book"
                            {{on "click" (fn this.openCollectionBook entry)}}
                          >
                            <span class="el-coll__book-title">{{entry.title}}</span>
                            <span class="el-coll__book-author">{{entry.author}}</span>
                          </button>
                        {{/each}}
                        {{#if c.historical.length}}
                          <p class="el-coll__subhead">Previously filed here</p>
                          {{#each c.historical as |entry|}}
                            <button
                              type="button"
                              class="el-coll__book is-historical"
                              {{on "click" (fn this.openCollectionBook entry)}}
                            >
                              <span class="el-coll__book-title">{{entry.title}}</span>
                              <span class="el-coll__book-author">{{entry.author}}</span>
                            </button>
                          {{/each}}
                        {{/if}}
                        <button
                          type="button"
                          class="el-coll__all"
                          {{on "click" (fn this.filterByTag c.name)}}
                        >Browse these as covers →</button>
                      </div>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="el-state">No collections match that filter.</p>
            {{/if}}
          </div>
        {{/if}}
      {{else if this.store.error}}
        <div class="el-state el-state--error">
          <p>The catalogue couldn't be loaded right now.</p>
          <p class="el-state__detail">{{this.store.error}}</p>
          <button type="button" class="el-btn" {{on "click" this.retry}}>Try again</button>
        </div>
      {{else}}
        <p class="el-state" aria-live="polite">Loading the catalogue…</p>
        <ul class="el-covers el-covers--skeleton" aria-hidden="true">
          {{#each this.skeleton}}
            <li><span class="el-cover__img"></span></li>
          {{/each}}
        </ul>
      {{/if}}
    </section>
  </template>
}
