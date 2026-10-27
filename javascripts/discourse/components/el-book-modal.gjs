import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DModal from "discourse/components/d-modal";
import { largeCover, parseTags } from "../lib/catalogue-data";

export default class ElBookModal extends Component {
  get book() {
    return this.args.model.book;
  }

  get coverUrl() {
    return this.book._hasCover ? largeCover(this.book.coverUrl) : null;
  }

  get rows() {
    const b = this.book;
    const language =
      b.language && b.language.toLowerCase() !== "english" ? b.language : "";
    return [
      ["Author", b.author],
      ["Year", b._year || (b.year || "").slice(0, 4)],
      ["Publisher", b.publisher],
      ["Genre", b.genre],
      ["Format", b.format],
      ["Language", language],
      ["ISBN-13", b.isbn],
      ["Call no.", b.callNumber],
      ["In library", b.collection],
    ]
      .filter(([, value]) => value)
      .map(([label, value]) => ({ label, value }));
  }

  get tags() {
    const info = parseTags((this.book._tags || []).join(","));
    return [
      ...(info.active ? [{ name: info.active, active: true }] : []),
      ...info.historical.map((name) => ({ name, active: false })),
    ];
  }

  @action
  pickTag(name) {
    this.args.closeModal();
    this.args.model.onTag?.(name);
  }

  @action
  coverError(event) {
    event.target.closest(".el-book__cover")?.classList.add("is-broken");
  }

  <template>
    <DModal
      @title={{this.book.title}}
      @closeModal={{@closeModal}}
      class="el-book-modal"
    >
      <:body>
        <div class="el-book">
          <div class="el-book__cover" data-title={{this.book.title}}>
            {{#if this.coverUrl}}
              <img
                src={{this.coverUrl}}
                alt="Cover of {{this.book.title}}"
                {{on "error" this.coverError}}
              />
            {{/if}}
          </div>
          <div class="el-book__info">
            <dl class="el-book__meta">
              {{#each this.rows as |row|}}
                <div class="el-book__row">
                  <dt>{{row.label}}</dt>
                  <dd>{{row.value}}</dd>
                </div>
              {{/each}}
              {{#if this.tags.length}}
                <div class="el-book__row">
                  <dt>Tag</dt>
                  <dd class="el-book__tags">
                    {{#each this.tags as |t|}}
                      <button
                        type="button"
                        class="el-pill {{if t.active 'is-active'}}"
                        title="Browse this collection"
                        {{on "click" (fn this.pickTag t.name)}}
                      >{{t.name}}</button>
                    {{/each}}
                  </dd>
                </div>
              {{/if}}
            </dl>
            {{#if this.book._referenceOnly}}
              <p class="el-book__note">Reference only — not available for loan.</p>
            {{/if}}
          </div>
        </div>
      </:body>
    </DModal>
  </template>
}
