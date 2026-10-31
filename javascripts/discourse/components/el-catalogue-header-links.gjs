import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import store, { catalogueUrl } from "../lib/catalogue-store";
import { membershipLink, onMembershipPage } from "../lib/membership";

// The library's links in the site header, as one group.
//
//   @row = false  →  beside the logo (computers and tablets):
//                    Browse books · Browse collections · Membership · Media
//   @row = true   →  a second header row on phones:
//                    Catalogue · Media · Membership
//
// Discourse drops unknown query strings and hashes when routing, so the
// chosen catalogue view (books / collections) is handed to the catalogue page
// through the shared store rather than the URL.
export default class ElCatalogueHeaderLinks extends Component {
  @service router;
  @service currentUser;

  get path() {
    return (this.router.currentURL || "").split(/[?#]/)[0];
  }

  under(url) {
    return this.path === url || this.path.startsWith(`${url}/`);
  }

  get url() {
    return catalogueUrl(settings.category_slug);
  }

  get onCatalogue() {
    return this.under(this.url);
  }

  get booksActive() {
    return this.onCatalogue && store.view !== "collections";
  }

  get collectionsActive() {
    return this.onCatalogue && store.view === "collections";
  }

  get showCatalogue() {
    return settings.show_header_links;
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

  get membership() {
    return settings.show_membership_link ? membershipLink(this.currentUser) : null;
  }

  get membershipActive() {
    return onMembershipPage(this.path);
  }

  get media() {
    if (!settings.show_media_link || !settings.media_category_slug) {
      return null;
    }
    const url = catalogueUrl(settings.media_category_slug);
    return { url, label: settings.media_label, active: this.under(url) };
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
    <nav
      class="el-header-links {{if @row 'el-header-links--row' 'el-header-links--inline'}}"
      aria-label="Library"
    >
      {{#if this.showCatalogue}}
        {{#if @row}}
          <a
            href={{this.url}}
            class="el-header-link {{if this.onCatalogue 'is-active'}}"
            aria-current={{if this.onCatalogue "page"}}
            {{on "click" (fn this.go null)}}
          >{{this.mobileLabel}}</a>
        {{else}}
          <a
            href={{this.url}}
            class="el-header-link el-header-link--wide {{if this.booksActive 'is-active'}}"
            aria-current={{if this.booksActive "page"}}
            {{on "click" (fn this.go "books")}}
          >{{this.booksLabel}}</a>
          <a
            href="{{this.url}}?view=collections"
            class="el-header-link el-header-link--wide {{if this.collectionsActive 'is-active'}}"
            aria-current={{if this.collectionsActive "page"}}
            {{on "click" (fn this.go "collections")}}
          >{{this.collectionsLabel}}</a>
          <a
            href={{this.url}}
            class="el-header-link el-header-link--narrow {{if this.onCatalogue 'is-active'}}"
            aria-current={{if this.onCatalogue "page"}}
            {{on "click" (fn this.go null)}}
          >{{this.mobileLabel}}</a>
        {{/if}}
      {{/if}}
      {{#if @row}}
        {{#if this.media}}
          <a
            href={{this.media.url}}
            class="el-header-link {{if this.media.active 'is-active'}}"
            aria-current={{if this.media.active "page"}}
          >{{this.media.label}}</a>
        {{/if}}
      {{/if}}
      {{#if this.membership}}
        <a
          href={{this.membership.href}}
          class="el-header-link el-header-link--membership {{if this.membershipActive 'is-active'}}"
          aria-current={{if this.membershipActive "page"}}
        >{{this.membership.label}}</a>
      {{/if}}
      {{#unless @row}}
        {{#if this.media}}
          <a
            href={{this.media.url}}
            class="el-header-link {{if this.media.active 'is-active'}}"
            aria-current={{if this.media.active "page"}}
          >{{this.media.label}}</a>
        {{/if}}
      {{/unless}}
    </nav>
  </template>
}
