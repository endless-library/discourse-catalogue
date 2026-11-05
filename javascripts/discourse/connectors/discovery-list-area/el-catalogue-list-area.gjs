import Component from "@glimmer/component";
import ElCatalogue from "../../components/el-catalogue";
import ElLibraryManager from "../../components/el-library-manager";
import ElMyLoans from "../../components/el-my-loans";
import { isCatalogueCategory } from "../../lib/catalogue-store";

// `discovery-list-area` is a wrapper outlet: on the catalogue category we
// render the catalogue in place of the topic list, on the librarians-only
// category the Library Manager, and on the My loans category the visitor's
// own loans; everywhere else {{yield}} renders Discourse's normal list
// unchanged. (A wrapper outlet takes only one connector, which is why all
// three live here.)
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

  get isMyLoans() {
    return isCatalogueCategory(this.category, settings.my_loans_category_slug);
  }

  <template>
    {{#if this.isCatalogue}}
      <ElCatalogue />
    {{else if this.isLibrarian}}
      <ElLibraryManager />
    {{else if this.isMyLoans}}
      <ElMyLoans />
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
