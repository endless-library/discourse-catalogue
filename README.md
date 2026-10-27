# Endless Library Catalogue — Discourse theme component

Shows the library catalogue (books and collections) as a native page in
Discourse, using the same data as the Apps Script public catalogue. There is
no iframe: Discourse downloads the catalogue JSON and renders it itself.

What visitors get:

- **Browse books** and **Browse collections** links in the site header (one
  *Catalogue* link on phones, where there's only room for one) and a *Library
  catalogue* link in the menu.
- A catalogue page at `/c/catalogue` with tabs for books and collections, live
  search as you type, advanced search, covers or list view, sortable columns,
  and a detail window for each book. Clicking a tag in the detail window
  browses that collection.
- The catalogue appears in the categories list on the home page, so it's one
  click from the front page.

## Speed

- Each visitor's browser keeps the last catalogue it downloaded and shows it
  instantly on later visits, then refreshes it in the background (every 5
  minutes by default, see `refresh_after_minutes`).
- The download starts quietly when someone opens any forum page, so it is
  usually ready before they click through.
- The Apps Script side (`CatalogueApi.gs`) serves a cached copy instead of
  rebuilding it from the sheets on every request. Without it, a first visit
  waits about 10 seconds.

## Setup

### 1. Apps Script (do this first)

1. In the Apps Script project, add a script file named `CatalogueApi` and paste
   in `CatalogueApi.gs`.
2. In `Code.gs` → `doGet`, replace the `catalogue-data` block with this line,
   placed **above** `setupSheets();`:

   ```js
   if (page === 'catalogue-data') return serveCatalogueData();
   ```

3. Run `installCatalogueCacheTrigger` once from the editor (approve the
   permissions prompt). It fills the cache now and refreshes it every 15
   minutes.
4. **Deploy → Manage deployments → ✏️ → Version: New version → Deploy.** The
   URL stays the same.

After a big edit to the sheet, run `refreshCatalogueCache` to publish it right
away instead of waiting up to 15 minutes.

### 2. Discourse

1. **Create the category.** New category named *Catalogue*, slug `catalogue`.
   Under Security, allow *everyone* to **See** and only staff to **Create**.
   Give it a description such as "Browse the library's books and collections."
   so it reads well in the home page list.
2. **Install the component.** Admin → Appearance → Themes & components →
   Components → **Install** → *From your device* → choose
   `discourse-catalogue-theme.zip`.
3. **Add it to your theme.** Open the component and, under *Include component
   on these themes*, add the site's active theme.
4. **Check the settings** on the component page. The defaults point at the
   current Apps Script URL and the `catalogue` slug.

For easier updates, put this folder in its own GitHub repository and install
with *From a git repository* instead; Discourse can then pull changes with
**Check for updates**. (A public repo needs no setup; a private one needs a
deploy key, which Discourse walks you through.)

## Settings

| Setting | What it does |
|---|---|
| `data_url` | Apps Script URL ending in `?page=catalogue-data`. |
| `category_slug` | Category whose page shows the catalogue (default `catalogue`). |
| `show_header_links` | Show the two links in the header. |
| `books_label`, `collections_label` | Header link and tab wording. |
| `mobile_label` | The single header link shown on phones (default *Catalogue*). |
| `show_menu_link` | Add *Library catalogue* to the menu's Community section. |
| `refresh_after_minutes` | How old a visitor's saved copy can get before it is refreshed in the background. |

## How it hooks into Discourse

- `connectors/discovery-list-area/` swaps the topic list for the catalogue on
  the catalogue category only. Every other category renders normally.
- `common.scss` hides the category title bar and Latest/Top buttons on that
  page (via the `body.category-catalogue` class).
- Discourse strips unknown `?query` and `#hash` parts when navigating inside
  the app, so the header links pass the chosen view (books or collections)
  through shared state. A full page load of `/c/catalogue?view=collections`
  (for example a shared link) still opens on collections.

## Files

```
about.json, settings.yml
common/common.scss                         styles
javascripts/discourse/
  api-initializers/el-catalogue.js         header links, menu link, warm-up download
  connectors/discovery-list-area/          puts the catalogue on the category page
  components/el-catalogue.gjs              the catalogue page
  components/el-book-modal.gjs             book detail window
  components/el-catalogue-header-links.gjs header links
  lib/catalogue-store.js                   download + local caching, shared view state
  lib/catalogue-data.js                    search, sorting, collection matching
```
