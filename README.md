# Endless Library Catalogue — Discourse theme component

Shows the library catalogue (books and collections) as a native page in
Discourse, using the same data as the Apps Script public catalogue. There is
no iframe: Discourse downloads the catalogue JSON and renders it itself.

What visitors get:

- One group of header links straight after the logo: **Browse books**,
  **Browse collections**, **Membership**, **Media** (on narrower screens the
  first two become one *Catalogue* link). On phones they move to a second
  header row: *Catalogue · Media · Membership*. Plus a *Library catalogue*
  link in the menu.
- A catalogue page at `/c/catalogue` with tabs for books and collections, live
  search as you type, advanced search, covers or list view, sortable columns,
  and a detail window for each book. Clicking a tag in the detail window
  browses that collection.
- The catalogue appears in the categories list on the home page, so it's one
  click from the front page.
- A **membership link** in the header (on phones too) and the menu: *New
  membership* for people without one, *My membership* for members.
- The **Library Manager** app inside a librarians-only category, with a
  *Library Manager* menu link for the people who can see it.

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

### 3. Membership link

1. Find the group the subscriptions plugin adds subscribers to (Admin →
   Plugins → Subscriptions → Products → the plan's *Group* field, or
   Admin → Groups). Put its **name** (not the full display name) in the
   `membership_group` setting.
2. In that group's settings → Visibility, make sure *Who can see this group*
   is anything except *Group owners and staff*, otherwise members can't see
   themselves in it and always get *New membership*.
3. If the subscriptions plugin's pricing table is on, set
   `new_membership_url` to `/s/subscriptions`.

On phones the membership link is in the second header row, so it's always
visible, logged in or not.

The subscriptions plugin's own *Subscribe* tab in the topic list nav can be
turned off with the site setting `discourse subscriptions extra nav
subscribe`, since the header link replaces it.

### 4. Library Manager (librarians) and My loans (members)

Both pages are native Discourse pages, styled like the catalogue. They talk to
the library's Apps Script (`LibraryApi.gs`), and Discourse vouches for who's
signed in using **DiscourseConnect**. Nobody needs a Google sign-in, and it
works on iPhones.

**Library Manager**: Lend (find the member → find books → lend), Loans
(return, renew, overdue) and Members (search, add, edit, *Sync from forum*).
Access and the collection owners' tools stay in the full Google app, linked
from the page.
**My loans**: what the visitor has out, due dates, Renew, and their
borrowing history.

Setup, once:

1. Make up a long random secret (40+ letters and numbers).
2. Discourse → Admin → Settings:
   - `enable discourse connect provider`: ticked
   - `discourse connect provider secrets`: add
     `shush.endlesslibrary.com.au|<secret>`
   - `discourse connect provider claims map`: make sure **email**,
     **groups** and **admin** are included.
3. Apps Script → Project Settings → Script properties: add
   `DISCOURSE_CONNECT_SECRET` = the same secret. Push, then publish a new
   version of the **Execute as: Me / Anyone** deployment (the one in
   `data_url`).
4. Categories:
   - *Library Manager*, slug `library-manager`: Security → remove
     *everyone*, give **Librarians** See.
   - *My loans*, slug `my-loans`: Security → *everyone* See, staff Create
     (the page only ever shows the signed-in person their own loans).

The library server checks again on every request: desk actions need the
Librarians group (or forum admin), and members only ever get their own
loans, matched by forum account and then email.

Sign-in is a quick hop through `/session/sso_provider` the first time the
page opens. It's good for 6 hours, then it repeats invisibly on the next
visit. If someone uses two-factor login, Discourse doesn't ask for it again
here.

## Settings

| Setting | What it does |
|---|---|
| `data_url` | Apps Script URL ending in `?page=catalogue-data`. |
| `category_slug` | Category whose page shows the catalogue (default `catalogue`). |
| `show_header_links` | Show the two links in the header. |
| `books_label`, `collections_label` | Header link and tab wording. |
| `mobile_label` | The single header link shown on phones (default *Catalogue*). |
| `show_menu_link` | Add *Library catalogue* to the menu's Community section. |
| `show_media_link`, `media_label`, `media_category_slug` | The Media link in the header group (turn off the Media gallery component's own header link). |
| `refresh_after_minutes` | How old a visitor's saved copy can get before it is refreshed in the background. |
| `show_membership_link` | Membership link in the header and menu. |
| `membership_group` | Group whose members see *My membership*. |
| `new_membership_label`, `my_membership_label` | The two link texts. |
| `new_membership_url` | Where *New membership* goes (`/s`, or `/s/subscriptions` with the pricing table). *My membership* always goes to the user's billing → subscriptions page. |
| `librarian_category_slug` | Category that shows the Library Manager (blank turns it off). |
| `my_loans_category_slug` | Category that shows My loans (blank turns it off). |
| `manager_api_url` | Library server for those pages; blank = the `data_url` deployment. Must be *Execute as: Me / Anyone*. |
| `librarian_app_url` | The full Google app, linked from the Library Manager page. |
| `show_librarian_menu_link`, `show_my_loans_link` | Menu links for those pages. |

## How it hooks into Discourse

- `connectors/discovery-list-area/` swaps the topic list for the catalogue on
  the catalogue category, the Library Manager on the librarians category
  and My loans on the my-loans category. Every other category renders normally. (It's a wrapper outlet,
  which only takes one connector, so both swaps live in this one component.)
- The header links render in the `before-header-panel` outlet (CSS pulls it
  up against the logo) and, on phones, a second row in the `after-header`
  connector (Discourse measures the header's height, so the page moves down
  to fit it). The row is left out while a topic's title is docked in the
  header.
- Membership is read from `currentUser.groups`, so the link costs no extra
  request.
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
  api-initializers/el-catalogue.js         header links, menu links, warm-up download
  connectors/discovery-list-area/          puts the catalogue on the category page
  connectors/after-header/                 phones' second header row
  components/el-catalogue.gjs              the catalogue page
  components/el-book-modal.gjs             book detail window
  components/el-catalogue-header-links.gjs header links (catalogue + membership)
  components/el-library-manager.gjs        Library Manager (Lend · Loans · Members)
  components/el-my-loans.gjs               My loans
  lib/catalogue-store.js                   download + local caching, shared view state
  lib/catalogue-data.js                    search, sorting, collection matching
  lib/membership.js                        New / My membership logic
  lib/library-api.js                       DiscourseConnect sign-in + library server calls
```
