import Component from "@glimmer/component";
import ElCatalogue from "../../components/el-catalogue";
import { isCatalogueCategory } from "../../lib/catalogue-store";

// `discovery-list-area` is a wrapper outlet: on the catalogue category we
// render the catalogue in place of the topic list; everywhere else {{yield}}
// renders Discourse's normal list unchanged.
export default class ElCatalogueListArea extends Component {
  get category() {
    return this.args.outletArgs?.category ?? this.args.category;
  }

  get isCatalogue() {
    return isCatalogueCategory(this.category, settings.category_slug);
  }

  <template>
    {{#if this.isCatalogue}}
      <ElCatalogue />
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
