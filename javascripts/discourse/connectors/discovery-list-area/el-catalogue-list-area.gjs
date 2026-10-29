import Component from "@glimmer/component";
import ElCatalogue from "../../components/el-catalogue";
import ElLibrarianApp from "../../components/el-librarian-app";
import { isCatalogueCategory } from "../../lib/catalogue-store";

// `discovery-list-area` is a wrapper outlet: on the catalogue category we
// render the catalogue in place of the topic list, and on the librarians-only
// category the Library Manager app; everywhere else {{yield}} renders
// Discourse's normal list unchanged. (A wrapper outlet takes only one
// connector, which is why both live here.)
export default class ElCatalogueListArea extends Component {
  get category() {
    return this.args.outletArgs?.category ?? this.args.category;
  }

  get isCatalogue() {
    return isCatalogueCategory(this.category, settings.category_slug);
  }

  get isLibrarian() {
    return isCatalogueCategory(this.category, settings.librarian_category_slug);
  }

  <template>
    {{#if this.isCatalogue}}
      <ElCatalogue />
    {{else if this.isLibrarian}}
      <ElLibrarianApp />
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
