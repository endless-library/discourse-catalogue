import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import ElCatalogueHeaderLinks from "../components/el-catalogue-header-links";
import store, { catalogueUrl } from "../lib/catalogue-store";
import { captureSsoReturn } from "../lib/library-api";
import { membershipLink } from "../lib/membership";

export default apiInitializer((api) => {
  // Coming back from signing in to the Library Manager / My loans pages:
  // pick up ?sso=…&sig=… before Discourse's router drops them.
  captureSsoReturn();

  // A full page load of /c/catalogue?view=collections (e.g. a shared link or
  // a new tab) opens on that view. Read it now, before Discourse's router
  // strips the unknown query parameter.
  const view = new URLSearchParams(window.location.search).get("view");
  if (view) {
    store.setView(view);
  }

  // Header links beside the logo (computers/tablets). The phones' second row
  // is a connector: connectors/after-header.
  if (settings.show_header_links || settings.show_membership_link || settings.show_media_link) {
    api.renderInOutlet("before-header-panel", ElCatalogueHeaderLinks);
  }

  if (settings.show_menu_link) {
    api.addCommunitySectionLink({
      name: "library-catalogue",
      href: catalogueUrl(settings.category_slug),
      title: "Browse the library catalogue",
      text: "Library catalogue",
      icon: "book",
    });
  }

  // "New membership" / "My membership" in the menu as well (phones open the
  // menu more often than they scan the header).
  if (settings.show_membership_link) {
    api.addCommunitySectionLink(
      (BaseSectionLink) =>
        class extends BaseSectionLink {
          get name() {
            return "library-membership";
          }
          get href() {
            return membershipLink(this.currentUser).href;
          }
          get title() {
            return membershipLink(this.currentUser).member
              ? "Manage your library membership"
              : "Become a library member";
          }
          get text() {
            return membershipLink(this.currentUser).label;
          }
          get defaultPrefixValue() {
            return "id-card";
          }
        }
    );
  }

  // "Library Manager" in the menu, only for people who can see the
  // librarians category (Discourse only sends categories you can see).
  if (settings.show_librarian_menu_link && settings.librarian_category_slug) {
    api.addCommunitySectionLink(
      (BaseSectionLink) =>
        class extends BaseSectionLink {
          @service site;

          get name() {
            return "library-manager";
          }
          get shouldDisplay() {
            return (this.site.categories || []).some(
              (c) => c.slug === settings.librarian_category_slug
            );
          }
          get href() {
            return catalogueUrl(settings.librarian_category_slug);
          }
          get title() {
            return "Loans, members and access (librarians only)";
          }
          get text() {
            return "Library Manager";
          }
          get defaultPrefixValue() {
            return "screwdriver-wrench";
          }
        }
    );
  }

  // "My loans" in the menu for anyone logged in.
  if (settings.show_my_loans_link && settings.my_loans_category_slug) {
    api.addCommunitySectionLink(
      (BaseSectionLink) =>
        class extends BaseSectionLink {
          get name() {
            return "library-my-loans";
          }
          get shouldDisplay() {
            return !!this.currentUser;
          }
          get href() {
            return catalogueUrl(settings.my_loans_category_slug);
          }
          get title() {
            return "Books you've borrowed from the library";
          }
          get text() {
            return "My loans";
          }
          get defaultPrefixValue() {
            return "book-open-reader";
          }
        }
    );
  }

  // Start downloading as soon as anyone lands on the site, so the catalogue
  // is usually ready by the time they click through to it.
  const warm = () =>
    store.ensureLoaded(settings.data_url, settings.refresh_after_minutes);
  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(warm, { timeout: 5000 });
  } else {
    setTimeout(warm, 2000);
  }
});
