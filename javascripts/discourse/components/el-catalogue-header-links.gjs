import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import store, { catalogueUrl } from "../lib/catalogue-store";
import { membershipLink, onMembershipPage } from "../lib/membership";

// "Browse books" / "Browse collections" in the site header (one "Catalogue"
// link on phones, where the header has no room for two). Discourse drops
// unknown query strings and hashes when routing, so the chosen view is handed
// to the catalogue page through the shared store rather than the URL.
//
// Also holds the membership link ("New membership" / "My membership"), which
// shows on phones too: the subscriptions plugin's own "Subscribe" button sits
// in the topic-list nav, which phones fold into a dropdown.
export default class ElCatalogueHeaderLinks extends Component {
  @service router;
  @service currentUser;

  get url() {
    return catalogueUrl(settings.category_slug);
  }

  get onCatalogue() {
    const current = this.router.currentURL || "";
    const path = current.split(/[?#]/)[0];
    return path === this.url || path.startsWith(`${this.url}/`);
  }

  get booksActive() {
    return this.onCatalogue && store.view !== "collections";
  }

  get collectionsActive() {
    return this.onCatalogue && store.view === "collections";
  }

  get booksLabel() {
    return settings.books_label;
  }

  get collectionsLabel() {
    return settings.collections_label;
  }

  get mobileLabel() {
    return settings.mobile_label;
  }

  get showCatalogueLinks() {
    return settings.show_header_links;
  }

  get membership() {
    return settings.show_membership_link ? membershipLink(this.currentUser) : null;
  }

  get membershipActive() {
    const path = (this.router.currentURL || "").split(/[?#]/)[0];
    return onMembershipPage(path);
  }

  @action
  go(view, event) {
    // Let ctrl/cmd/shift/middle clicks open a new tab as normal.
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    if (view) {
      store.setView(view);
    }
    if (!this.onCatalogue) {
      DiscourseURL.routeTo(this.url);
    }
  }

  <template>
    <nav class="el-header-links" aria-label="Library">
      {{#if this.showCatalogueLinks}}
        <a
          href={{this.url}}
          class="el-header-link el-header-link--wide {{if this.booksActive 'is-active'}}"
          aria-current={{if this.booksActive "page"}}
          {{on "click" (fn this.go "books")}}
        >
          {{this.booksLabel}}
        </a>
        <a
          href="{{this.url}}?view=collections"
          class="el-header-link el-header-link--wide {{if this.collectionsActive 'is-active'}}"
          aria-current={{if this.collectionsActive "page"}}
          {{on "click" (fn this.go "collections")}}
        >
          {{this.collectionsLabel}}
        </a>
        <a
          href={{this.url}}
          class="el-header-link el-header-link--mobile {{if this.onCatalogue 'is-active'}}"
          aria-current={{if this.onCatalogue "page"}}
          {{on "click" (fn this.go null)}}
        >
          {{this.mobileLabel}}
        </a>
      {{/if}}
      {{#if this.membership}}
        <a
          href={{this.membership.href}}
          class="el-header-link el-header-link--membership
            {{if this.membership.member 'is-member' 'is-new'}}
            {{if this.membershipActive 'is-active'}}"
          aria-current={{if this.membershipActive "page"}}
        >
          {{this.membership.label}}
        </a>
      {{/if}}
    </nav>
  </template>
}
