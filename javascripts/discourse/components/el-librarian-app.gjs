import Component from "@glimmer/component";
import icon from "discourse/helpers/d-icon";

// The Library Manager (Apps Script web app) shown inside the librarians-only
// category. Discourse's category security decides who can open this page;
// the app itself still checks the visitor's Google account against the
// Access sheet, so the embed adds a gate rather than replacing one.
//
// The app runs as the visiting Google user, so it needs their Google sign-in.
// Browsers that block third-party cookies in frames (Safari, all iPhone
// browsers, Firefox strict mode) can show a blank page or a sign-in loop
// here; the "Open in new tab" button is the way round that.
export default class ElLibrarianApp extends Component {
  get url() {
    return settings.librarian_app_url;
  }

  <template>
    <div class="el-librarian">
      <div class="el-librarian__bar">
        <p class="el-librarian__hint">
          Signed in to Google with the account on the Access sheet? You're set.
          Blank, or stuck on a Google sign-in? Open it in a new tab instead
          (Safari and iPhones block Google sign-in inside embedded pages).
        </p>
        <a
          class="btn btn-default el-librarian__open"
          href={{this.url}}
          target="_blank"
          rel="noopener noreferrer"
        >
          {{icon "up-right-from-square"}}
          <span>Open in new tab</span>
        </a>
      </div>
      {{#if this.url}}
        <iframe
          class="el-librarian__frame"
          src={{this.url}}
          title="Library Manager"
          allow="clipboard-write"
        ></iframe>
      {{else}}
        <p class="el-librarian__hint">
          No Library Manager URL is set in the theme component's settings.
        </p>
      {{/if}}
    </div>
  </template>
}
