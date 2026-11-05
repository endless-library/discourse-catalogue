import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import store from "../lib/catalogue-store";
import auth, {
  dueText,
  formatDate,
  isOverdue,
  LibraryAuthError,
  loanKey,
  renewalsLeft,
} from "../lib/library-api";

// The librarians' desk, native in Discourse: Lend · Loans · Members.
// Everything goes through LibraryApi.gs, which applies the same rules as the
// Google app (loan periods, renewal limits, overdue blocks, reference-only
// books). Access and the collection owners' tools stay in the full app.

const isEq = (a, b) => a === b;
const concatKey = (a, b) => `${a}${b}`;
const MEMBER_LIMIT = 8;
const BOOK_LIMIT = 25;
const LOAN_LIMIT = 100;

function words(q) {
  return String(q || "")
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
}

function matches(haystack, q) {
  const w = words(q);
  return w.length > 0 && w.every((x) => haystack.includes(x));
}

function membershipLabel(m) {
  return m.membership || "";
}

export default class ElLibraryManager extends Component {
  @service currentUser;
  @service dialog;

  @tracked tab = "lend";
  @tracked members = [];
  @tracked loans = [];
  @tracked rules = null;
  @tracked books = null;
  @tracked loading = true;
  @tracked loadError = null;
  @tracked busy = null;
  @tracked notice = null; // { kind: "ok" | "error" | "warn", text }
  @tracked expired = false;

  // Lend
  @tracked memberQuery = "";
  @tracked lendMemberId = null;
  @tracked bookQuery = "";
  @tracked basket = [];
  @tracked lendResults = null;

  // Loans
  @tracked loanFilter = "active";
  @tracked loanQuery = "";

  // Members
  @tracked memberListQuery = "";
  @tracked openMemberId = null;
  @tracked form = null; // { mode: "add" | "edit", memberId, name, phone, email }

  auth = auth;

  constructor() {
    super(...arguments);
    this.start();
  }

  async start() {
    this.loading = true;
    this.loadError = null;
    this.expired = false;
    const ready = await auth.ensure(this.currentUser);
    if (!ready) {
      this.loading = false;
      return;
    }
    if (!auth.user?.librarian) {
      this.loading = false;
      this.loadError = "The Library Manager is for librarians. Your forum account isn't in the Librarians group.";
      return;
    }
    // Covers come from the public catalogue the site already downloads.
    store.ensureLoaded(settings.data_url, settings.refresh_after_minutes);
    try {
      const [s, b] = await Promise.all([auth.call("state"), auth.call("books")]);
      if (!s.ok || !b.ok) {
        throw new Error(s.error || b.error || "Couldn't load the library.");
      }
      this.applyState(s.state);
      this.books = b.books.map((book) => ({
        ...book,
        _hay: [book.title, book.author, book.isbn, book.collection].join(" ").toLowerCase(),
        _loanKey: loanKey(book.isbn, book.title, book.collection),
      }));
    } catch (e) {
      this.handleError(e, true);
    } finally {
      this.loading = false;
    }
  }

  applyState(state) {
    if (!state) {
      return;
    }
    this.members = state.members || [];
    this.loans = state.loans || [];
    this.rules = state.settings || null;
  }

  handleError(e, onLoad) {
    if (e instanceof LibraryAuthError) {
      this.expired = true;
      return;
    }
    if (onLoad) {
      this.loadError = e.message || String(e);
    } else {
      this.notice = { kind: "error", text: e.message || String(e) };
    }
  }

  // Runs one change, applies the fresh state the server sends back.
  async run(label, actionName, data) {
    this.busy = label;
    this.notice = null;
    try {
      const r = await auth.call(actionName, data);
      this.applyState(r.state);
      if (!r.ok) {
        this.notice = { kind: "error", text: r.error || "That didn't work." };
      }
      return r;
    } catch (e) {
      this.handleError(e, false);
      return null;
    } finally {
      this.busy = null;
    }
  }

  @action
  signInAgain() {
    auth.restart();
    this.start();
  }

  // ── Shared lookups ────────────────────────────────────────────────────────

  get activeLoans() {
    return this.loans.filter((l) => l.status === "Active");
  }

  get loansByMember() {
    const map = new Map();
    for (const l of this.activeLoans) {
      if (!map.has(l.memberId)) {
        map.set(l.memberId, []);
      }
      map.get(l.memberId).push(l);
    }
    return map;
  }

  get loanByKey() {
    const map = new Map();
    for (const l of this.activeLoans) {
      map.set(loanKey(l.isbn, l.title, l.collection), l);
    }
    return map;
  }

  get overdueCount() {
    return this.activeLoans.filter(isOverdue).length;
  }

  decorateMember(m) {
    const active = this.loansByMember.get(m.memberId) || [];
    const overdue = active.filter(isOverdue).length;
    const label = membershipLabel(m);
    return {
      ...m,
      activeCount: active.length,
      overdue,
      loans: active
        .slice()
        .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate))
        .map((l) => this.decorateLoan(l)),
      badge: label,
      badgeClass: label ? `is-${label.toLowerCase()}` : "",
      lapsed: label === "Lapsed",
      contact: [m.email, m.phone].filter(Boolean).join(" · "),
    };
  }

  decorateLoan(l) {
    const overdue = isOverdue(l);
    const left = renewalsLeft(l, this.rules);
    return {
      ...l,
      overdue,
      active: l.status === "Active",
      due: dueText(l),
      dueDate: formatDate(l.dueDate),
      loanDate: formatDate(l.loanDate),
      renewalsLeft: left,
      canRenew: l.status === "Active" && left > 0,
      cover: this.coverFor(l),
    };
  }

  coverFor(item) {
    // Reading store.books ties this to the catalogue download finishing.
    if (!store.books) {
      return null;
    }
    const book = store.byKey ? store.findBook({ isbn: item.isbn, title: item.title, author: item.author || "" }) : null;
    return book && book._hasCover ? book.coverUrl : null;
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  get isLend() {
    return this.tab === "lend";
  }

  get isLoans() {
    return this.tab === "loans";
  }

  get isMembers() {
    return this.tab === "members";
  }

  @action
  setTab(tab) {
    this.tab = tab;
    this.notice = null;
  }

  @action
  setField(field, event) {
    this[field] = event.target.value;
  }

  @action
  dismissNotice() {
    this.notice = null;
  }

  // ── Lend ──────────────────────────────────────────────────────────────────

  get lendMember() {
    const m = this.members.find((x) => x.memberId === this.lendMemberId);
    return m ? this.decorateMember(m) : null;
  }

  get memberResults() {
    const q = this.memberQuery;
    if (!words(q).length) {
      return [];
    }
    return this.members
      .filter((m) => matches([m.name, m.email, m.phone, m.discourse].join(" ").toLowerCase(), q))
      .sort((a, b) => (a.membership === "Lapsed") - (b.membership === "Lapsed") || a.name.localeCompare(b.name))
      .slice(0, MEMBER_LIMIT)
      .map((m) => this.decorateMember(m));
  }

  @action
  pickLendMember(memberId) {
    this.lendMemberId = memberId;
    this.memberQuery = "";
    this.lendResults = null;
  }

  @action
  clearLendMember() {
    this.lendMemberId = null;
    this.lendResults = null;
  }

  get inBasket() {
    return new Set(this.basket.map((b) => b.key));
  }

  get bookResults() {
    if (!this.books) {
      return [];
    }
    const q = this.bookQuery;
    if (!words(q).length) {
      return [];
    }
    const inBasket = this.inBasket;
    const out = [];
    for (const b of this.books) {
      if (!matches(b._hay, q)) {
        continue;
      }
      const loan = this.loanByKey.get(b._loanKey);
      out.push({
        ...b,
        cover: this.coverFor(b),
        added: inBasket.has(b.key),
        onLoan: !!loan,
        status: b.refOnly
          ? "Reference only"
          : loan
            ? `On loan to ${loan.memberName} · due ${formatDate(loan.dueDate)}`
            : "Available",
        available: !b.refOnly && !loan,
        rule: b.rule && b.rule !== "Default" ? b.rule : "",
      });
      if (out.length >= BOOK_LIMIT) {
        break;
      }
    }
    return out;
  }

  get bookResultsMeta() {
    if (!words(this.bookQuery).length) {
      return "";
    }
    const n = this.bookResults.length;
    return n === 0 ? "No books match." : n >= BOOK_LIMIT ? `First ${BOOK_LIMIT} matches — keep typing to narrow down.` : "";
  }

  @action
  addToBasket(book) {
    if (!book.available || this.inBasket.has(book.key)) {
      return;
    }
    this.basket = [...this.basket, { key: book.key, title: book.title, author: book.author, cover: book.cover, rule: book.rule }];
    this.lendResults = null;
  }

  @action
  removeFromBasket(key) {
    this.basket = this.basket.filter((b) => b.key !== key);
  }

  get lendBlocked() {
    const m = this.lendMember;
    if (!m) {
      return "Choose who's borrowing.";
    }
    if (m.lapsed) {
      return `${m.name}'s membership has lapsed.`;
    }
    if (m.overdue && this.rules?.blockOverdueBorrowers !== false) {
      return `${m.name} has ${m.overdue} overdue book${m.overdue === 1 ? "" : "s"} — these need returning first.`;
    }
    return null;
  }

  get lendLimitWarning() {
    const m = this.lendMember;
    const limit = this.rules?.warnLimit;
    if (!m || !limit || !this.basket.length) {
      return null;
    }
    const total = m.activeCount + this.basket.length;
    return total > limit ? `That makes ${total} books on loan (the usual limit is ${limit}).` : null;
  }

  get lendButtonLabel() {
    const n = this.basket.length;
    const who = this.lendMember ? ` to ${this.lendMember.name}` : "";
    return this.busy === "lend" ? "Lending…" : `Lend ${n} book${n === 1 ? "" : "s"}${who}`;
  }

  get canLend() {
    return !!this.basket.length && !this.lendBlocked && !this.busy;
  }

  @action
  async lend() {
    if (!this.canLend) {
      return;
    }
    const titles = new Map(this.basket.map((b) => [b.key, b.title]));
    const r = await this.run("lend", "lend", {
      memberId: this.lendMemberId,
      bookKeys: this.basket.map((b) => b.key),
    });
    if (!r?.result?.results) {
      return;
    }
    const results = r.result.results.map((x) => ({
      title: titles.get(x.key) || x.key,
      ok: x.success,
      text: x.success ? `Due ${formatDate(x.dueDate)}${x.policy && x.policy !== "Default" ? ` (${x.policy})` : ""}` : x.error,
    }));
    const done = new Set(r.result.results.filter((x) => x.success).map((x) => x.key));
    this.basket = this.basket.filter((b) => !done.has(b.key));
    this.lendResults = results;
    if (done.size) {
      this.notice = {
        kind: r.result.warning ? "warn" : "ok",
        text: r.result.warning || `Lent ${done.size} book${done.size === 1 ? "" : "s"} to ${this.lendMember?.name}.`,
      };
    }
  }

  // ── Loans ─────────────────────────────────────────────────────────────────

  get loanFilters() {
    const active = this.activeLoans.length;
    return [
      { id: "active", label: `On loan (${active})` },
      { id: "overdue", label: `Overdue (${this.overdueCount})` },
      { id: "returned", label: "Returned" },
    ];
  }

  get loanList() {
    let list = this.loans;
    if (this.loanFilter === "active") {
      list = list.filter((l) => l.status === "Active");
    } else if (this.loanFilter === "overdue") {
      list = list.filter(isOverdue);
    } else {
      list = list.filter((l) => l.status !== "Active");
    }
    const q = this.loanQuery;
    if (words(q).length) {
      list = list.filter((l) => matches([l.title, l.memberName, l.collection, l.isbn].join(" ").toLowerCase(), q));
    }
    list = list.slice().sort((a, b) =>
      this.loanFilter === "returned"
        ? new Date(b.loanDate) - new Date(a.loanDate)
        : new Date(a.dueDate) - new Date(b.dueDate)
    );
    return list.slice(0, LOAN_LIMIT).map((l) => this.decorateLoan(l));
  }

  get loanListMeta() {
    const shown = this.loanList.length;
    return shown === 0 ? "Nothing here." : shown >= LOAN_LIMIT ? `Showing the first ${LOAN_LIMIT} — search to narrow down.` : "";
  }

  @action
  setLoanFilter(id) {
    this.loanFilter = id;
  }

  @action
  async renew(loan) {
    const r = await this.run(`renew:${loan.loanId}`, "renew", { loanId: loan.loanId });
    if (r?.ok) {
      this.notice = { kind: "ok", text: `Renewed “${loan.title}” — now due ${formatDate(r.result.newDueDate)}.` };
    }
  }

  @action
  returnLoan(loan) {
    this.dialog.yesNoConfirm({
      message: `Mark “${loan.title}” (${loan.memberName}) as returned?`,
      didConfirm: async () => {
        const r = await this.run(`return:${loan.loanId}`, "return", { loanId: loan.loanId });
        if (r?.ok) {
          this.notice = { kind: "ok", text: `“${loan.title}” is back on the shelf.` };
        }
      },
    });
  }

  // ── Members ───────────────────────────────────────────────────────────────

  get memberList() {
    const q = this.memberListQuery;
    let list = this.members;
    if (words(q).length) {
      list = list.filter((m) => matches([m.name, m.email, m.phone, m.discourse].join(" ").toLowerCase(), q));
    }
    return list
      .slice()
      .sort((a, b) => a.name.localeCompare(b.name))
      .map((m) => {
        const d = this.decorateMember(m);
        d.open = m.memberId === this.openMemberId;
        return d;
      });
  }

  get memberCountText() {
    const n = this.memberList.length;
    return `${n} member${n === 1 ? "" : "s"}`;
  }

  @action
  toggleMember(memberId) {
    this.openMemberId = this.openMemberId === memberId ? null : memberId;
    this.form = null;
  }

  @action
  lendTo(memberId) {
    this.lendMemberId = memberId;
    this.lendResults = null;
    this.tab = "lend";
  }

  @action
  startAdd() {
    this.openMemberId = null;
    this.form = { mode: "add", name: "", phone: "", email: "" };
  }

  @action
  startEdit(m) {
    this.form = { mode: "edit", memberId: m.memberId, name: m.name, phone: m.phone, email: m.email };
  }

  @action
  cancelForm() {
    this.form = null;
  }

  @action
  setForm(field, event) {
    this.form = { ...this.form, [field]: event.target.value };
  }

  get isAdding() {
    return this.form?.mode === "add";
  }

  @action
  async saveForm(event) {
    event?.preventDefault();
    const f = this.form;
    if (!f) {
      return;
    }
    const adding = f.mode === "add";
    const r = await this.run("save", adding ? "addMember" : "updateMember", f);
    if (r?.ok) {
      this.form = null;
      this.notice = { kind: "ok", text: adding ? `Added ${f.name}.` : `Saved ${f.name}.` };
      if (adding && r.result?.id) {
        this.openMemberId = r.result.id;
      }
    }
  }

  @action
  async sync() {
    const r = await this.run("sync", "sync", {});
    if (r?.ok) {
      this.notice = { kind: "ok", text: r.result.text };
    }
  }

  get syncLabel() {
    return this.busy === "sync" ? "Syncing…" : "Sync from forum";
  }

  get appUrl() {
    return settings.librarian_app_url;
  }

  get signingIn() {
    return ["checking", "redirecting"].includes(auth.status) || (this.loading && !this.loadError);
  }

  get authError() {
    return auth.status === "error" ? auth.error : null;
  }

  isBusy = (key) => this.busy === key;

  <template>
    <section class="el-manager" aria-labelledby="el-manager-heading">
      <header class="el-page-head">
        <h1 id="el-manager-heading" class="el-page-head__title">Library Manager</h1>
        {{#if this.appUrl}}
          <a class="el-page-head__link" href={{this.appUrl}} target="_blank" rel="noopener noreferrer">
            Open the full app ↗
          </a>
        {{/if}}
      </header>

      {{#if this.expired}}
        <div class="el-state el-state--error">
          <p>Your session has expired.</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Sign in again</button>
        </div>
      {{else if this.authError}}
        <div class="el-state el-state--error">
          <p>{{this.authError}}</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Try again</button>
        </div>
      {{else if this.loadError}}
        <div class="el-state el-state--error">
          <p>{{this.loadError}}</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Try again</button>
        </div>
      {{else if this.signingIn}}
        <div class="el-state"><p>Opening the library…</p></div>
      {{else}}
        <div class="el-tabs" role="tablist" aria-label="Library Manager">
          <button type="button" role="tab" class="el-tab {{if this.isLend 'is-active'}}"
            aria-selected={{if this.isLend "true" "false"}} {{on "click" (fn this.setTab "lend")}}>Lend</button>
          <button type="button" role="tab" class="el-tab {{if this.isLoans 'is-active'}}"
            aria-selected={{if this.isLoans "true" "false"}} {{on "click" (fn this.setTab "loans")}}>
            Loans
            {{#if this.overdueCount}}<span class="el-count is-overdue">{{this.overdueCount}}</span>{{/if}}
          </button>
          <button type="button" role="tab" class="el-tab {{if this.isMembers 'is-active'}}"
            aria-selected={{if this.isMembers "true" "false"}} {{on "click" (fn this.setTab "members")}}>Members</button>
        </div>

        {{#if this.notice}}
          <div class="el-notice is-{{this.notice.kind}}" role="status">
            <span>{{this.notice.text}}</span>
            <button type="button" class="el-notice__close" aria-label="Dismiss" {{on "click" this.dismissNotice}}>✕</button>
          </div>
        {{/if}}

        {{! ── Lend ── }}
        {{#if this.isLend}}
          <div class="el-lend">
            <section class="el-step">
              <h2 class="el-step__title"><span class="el-step__n">1</span> Who's borrowing?</h2>
              {{#if this.lendMember}}
                <div class="el-picked">
                  <div class="el-picked__main">
                    <span class="el-person__name">{{this.lendMember.name}}</span>
                    {{#if this.lendMember.badge}}
                      <span class="el-badge {{this.lendMember.badgeClass}}">{{this.lendMember.badge}}</span>
                    {{/if}}
                    <span class="el-person__contact">{{this.lendMember.contact}}</span>
                    <span class="el-person__loans">
                      {{this.lendMember.activeCount}} on loan
                      {{#if this.lendMember.overdue}} · <strong class="el-overdue-text">{{this.lendMember.overdue}} overdue</strong>{{/if}}
                    </span>
                  </div>
                  <button type="button" class="el-btn" {{on "click" this.clearLendMember}}>Change</button>
                </div>
              {{else}}
                <div class="el-search__bar">
                  <input type="search" class="el-search__input" placeholder="Name, email or phone…"
                    aria-label="Find a member" autocomplete="off" value={{this.memberQuery}}
                    {{on "input" (fn this.setField "memberQuery")}} />
                </div>
                {{#if this.memberResults.length}}
                  <ul class="el-picklist">
                    {{#each this.memberResults as |m|}}
                      <li>
                        <button type="button" class="el-picklist__item" {{on "click" (fn this.pickLendMember m.memberId)}}>
                          <span class="el-person__name">{{m.name}}</span>
                          {{#if m.badge}}<span class="el-badge {{m.badgeClass}}">{{m.badge}}</span>{{/if}}
                          <span class="el-person__contact">{{m.contact}}</span>
                          {{#if m.activeCount}}<span class="el-person__loans">{{m.activeCount}} on loan</span>{{/if}}
                        </button>
                      </li>
                    {{/each}}
                  </ul>
                {{else if this.memberQuery}}
                  <p class="el-hint">
                    No one matches. Just joined on the forum?
                    <button type="button" class="el-linkbtn" {{on "click" (fn this.setTab "members")}}>Sync or add them under Members</button>.
                  </p>
                {{/if}}
              {{/if}}
            </section>

            <section class="el-step">
              <h2 class="el-step__title"><span class="el-step__n">2</span> Which books?</h2>
              <div class="el-search__bar">
                <input type="search" class="el-search__input" placeholder="Title, author or ISBN…"
                  aria-label="Find a book" autocomplete="off" value={{this.bookQuery}}
                  {{on "input" (fn this.setField "bookQuery")}} />
              </div>
              {{#if this.bookResultsMeta}}<p class="el-hint">{{this.bookResultsMeta}}</p>{{/if}}
              {{#if this.bookResults.length}}
                <ul class="el-booklist">
                  {{#each this.bookResults as |b|}}
                    <li class="el-bookrow {{unless b.available 'is-unavailable'}}">
                      <span class="el-thumb">{{#if b.cover}}<img src={{b.cover}} alt="" loading="lazy" />{{/if}}</span>
                      <span class="el-bookrow__main">
                        <span class="el-bookrow__title">{{b.title}}</span>
                        <span class="el-bookrow__meta">{{b.author}}{{#if b.collection}} · {{b.collection}}{{/if}}</span>
                        <span class="el-bookrow__status {{if b.available 'is-available'}}">
                          {{b.status}}{{#if b.rule}} · {{b.rule}}{{/if}}
                        </span>
                      </span>
                      {{#if b.available}}
                        <button type="button" class="el-btn {{if b.added 'is-active'}}" disabled={{b.added}}
                          {{on "click" (fn this.addToBasket b)}}>{{if b.added "Added" "Add"}}</button>
                      {{/if}}
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
            </section>

            <section class="el-step el-step--basket">
              <h2 class="el-step__title"><span class="el-step__n">3</span> Lend</h2>
              {{#if this.basket.length}}
                <ul class="el-booklist">
                  {{#each this.basket as |b|}}
                    <li class="el-bookrow">
                      <span class="el-thumb">{{#if b.cover}}<img src={{b.cover}} alt="" loading="lazy" />{{/if}}</span>
                      <span class="el-bookrow__main">
                        <span class="el-bookrow__title">{{b.title}}</span>
                        <span class="el-bookrow__meta">{{b.author}}{{#if b.rule}} · {{b.rule}}{{/if}}</span>
                      </span>
                      <button type="button" class="el-btn" aria-label="Remove {{b.title}}"
                        {{on "click" (fn this.removeFromBasket b.key)}}>Remove</button>
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class="el-hint">Add books above.</p>
              {{/if}}
              {{#if this.lendBlocked}}
                {{#if this.basket.length}}<p class="el-hint el-hint--warn">{{this.lendBlocked}}</p>{{/if}}
              {{/if}}
              {{#if this.lendLimitWarning}}<p class="el-hint el-hint--warn">{{this.lendLimitWarning}}</p>{{/if}}
              <button type="button" class="el-btn el-btn--primary" disabled={{if this.canLend false true}}
                {{on "click" this.lend}}>{{this.lendButtonLabel}}</button>
              {{#if this.lendResults}}
                <ul class="el-results">
                  {{#each this.lendResults as |r|}}
                    <li class={{if r.ok "is-ok" "is-error"}}>
                      <span class="el-results__mark" aria-hidden="true">{{if r.ok "✓" "✕"}}</span>
                      <strong>{{r.title}}</strong> — {{r.text}}
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
            </section>
          </div>
        {{/if}}

        {{! ── Loans ── }}
        {{#if this.isLoans}}
          <div class="el-toolbar">
            <div class="el-search__bar">
              <input type="search" class="el-search__input" placeholder="Search by title or member…"
                aria-label="Search loans" autocomplete="off" value={{this.loanQuery}}
                {{on "input" (fn this.setField "loanQuery")}} />
            </div>
            <div class="el-view-toggle" role="group" aria-label="Show">
              {{#each this.loanFilters as |f|}}
                <button type="button" class="el-btn {{if (isEq f.id this.loanFilter) 'is-active'}}"
                  aria-pressed={{if (isEq f.id this.loanFilter) "true" "false"}}
                  {{on "click" (fn this.setLoanFilter f.id)}}>{{f.label}}</button>
              {{/each}}
            </div>
          </div>
          {{#if this.loanListMeta}}<p class="el-hint">{{this.loanListMeta}}</p>{{/if}}
          <ul class="el-loanlist">
            {{#each this.loanList as |l|}}
              <li class="el-loan {{if l.overdue 'is-overdue'}} {{unless l.active 'is-returned'}}">
                <span class="el-thumb">{{#if l.cover}}<img src={{l.cover}} alt="" loading="lazy" />{{/if}}</span>
                <span class="el-loan__main">
                  <span class="el-bookrow__title">{{l.title}}</span>
                  <span class="el-bookrow__meta">{{l.memberName}}{{#if l.collection}} · {{l.collection}}{{/if}}</span>
                  <span class="el-loan__due">
                    <strong>{{l.due}}</strong>
                    {{#if l.active}} · {{l.dueDate}} · {{l.renewalsLeft}} renewal{{if (isEq l.renewalsLeft 1) "" "s"}} left{{else}} · lent {{l.loanDate}}{{/if}}
                  </span>
                </span>
                {{#if l.active}}
                  <span class="el-loan__actions">
                    {{#if l.canRenew}}
                      <button type="button" class="el-btn" disabled={{this.busy}} {{on "click" (fn this.renew l)}}>
                        {{if (this.isBusy (concatKey "renew:" l.loanId)) "Renewing…" "Renew"}}
                      </button>
                    {{/if}}
                    <button type="button" class="el-btn el-btn--primary" disabled={{this.busy}} {{on "click" (fn this.returnLoan l)}}>
                      {{if (this.isBusy (concatKey "return:" l.loanId)) "Returning…" "Return"}}
                    </button>
                  </span>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}

        {{! ── Members ── }}
        {{#if this.isMembers}}
          <div class="el-toolbar">
            <div class="el-search__bar">
              <input type="search" class="el-search__input" placeholder="Search members…"
                aria-label="Search members" autocomplete="off" value={{this.memberListQuery}}
                {{on "input" (fn this.setField "memberListQuery")}} />
            </div>
            <div class="el-toolbar__actions">
              <button type="button" class="el-btn" disabled={{this.busy}} {{on "click" this.sync}}>{{this.syncLabel}}</button>
              <button type="button" class="el-btn el-btn--primary" {{on "click" this.startAdd}}>+ Add member</button>
            </div>
          </div>

          {{#if this.isAdding}}
            <form class="el-form" {{on "submit" this.saveForm}}>
              <h2 class="el-form__title">New member</h2>
              <p class="el-hint">People who join on the forum are added automatically — use <em>Sync from forum</em> if they've only just joined.</p>
              <label class="el-adv__field"><span>Name</span>
                <input type="text" required value={{this.form.name}} {{on "input" (fn this.setForm "name")}} /></label>
              <label class="el-adv__field"><span>Phone</span>
                <input type="tel" value={{this.form.phone}} {{on "input" (fn this.setForm "phone")}} /></label>
              <label class="el-adv__field"><span>Email</span>
                <input type="email" value={{this.form.email}} {{on "input" (fn this.setForm "email")}} /></label>
              <div class="el-form__actions">
                <button type="button" class="el-btn" {{on "click" this.cancelForm}}>Cancel</button>
                <button type="submit" class="el-btn el-btn--primary" disabled={{this.busy}}>{{if (this.isBusy "save") "Saving…" "Add member"}}</button>
              </div>
            </form>
          {{/if}}

          <p class="el-results-meta">{{this.memberCountText}}</p>
          <ul class="el-memberlist">
            {{#each this.memberList as |m|}}
              <li class="el-member {{if m.open 'is-open'}}">
                <button type="button" class="el-member__row" aria-expanded={{if m.open "true" "false"}}
                  {{on "click" (fn this.toggleMember m.memberId)}}>
                  <span class="el-person__name">{{m.name}}</span>
                  {{#if m.badge}}<span class="el-badge {{m.badgeClass}}">{{m.badge}}</span>{{/if}}
                  <span class="el-person__contact">{{m.contact}}</span>
                  <span class="el-person__loans">
                    {{#if m.activeCount}}{{m.activeCount}} on loan{{/if}}
                    {{#if m.overdue}} · <strong class="el-overdue-text">{{m.overdue}} overdue</strong>{{/if}}
                  </span>
                </button>
                {{#if m.open}}
                  <div class="el-member__body">
                    {{#if (isEq this.form.memberId m.memberId)}}
                      <form class="el-form el-form--inline" {{on "submit" this.saveForm}}>
                        <label class="el-adv__field"><span>Name</span>
                          <input type="text" required value={{this.form.name}} {{on "input" (fn this.setForm "name")}} /></label>
                        <label class="el-adv__field"><span>Phone</span>
                          <input type="tel" value={{this.form.phone}} {{on "input" (fn this.setForm "phone")}} /></label>
                        <label class="el-adv__field"><span>Email</span>
                          <input type="email" value={{this.form.email}} {{on "input" (fn this.setForm "email")}} /></label>
                        <div class="el-form__actions">
                          <button type="button" class="el-btn" {{on "click" this.cancelForm}}>Cancel</button>
                          <button type="submit" class="el-btn el-btn--primary" disabled={{this.busy}}>{{if (this.isBusy "save") "Saving…" "Save"}}</button>
                        </div>
                      </form>
                    {{else}}
                      <div class="el-member__actions">
                        {{#unless m.lapsed}}
                          <button type="button" class="el-btn el-btn--primary" {{on "click" (fn this.lendTo m.memberId)}}>Lend to {{m.name}}</button>
                        {{/unless}}
                        <button type="button" class="el-btn" {{on "click" (fn this.startEdit m)}}>Edit details</button>
                        {{#if m.discourse}}
                          <a class="el-btn" href="/u/{{m.discourse}}">Forum profile</a>
                        {{/if}}
                      </div>
                    {{/if}}
                    {{#if m.loans.length}}
                      <ul class="el-loanlist el-loanlist--compact">
                        {{#each m.loans as |l|}}
                          <li class="el-loan {{if l.overdue 'is-overdue'}}">
                            <span class="el-loan__main">
                              <span class="el-bookrow__title">{{l.title}}</span>
                              <span class="el-loan__due"><strong>{{l.due}}</strong> · {{l.dueDate}}</span>
                            </span>
                            <span class="el-loan__actions">
                              {{#if l.canRenew}}
                                <button type="button" class="el-btn" disabled={{this.busy}} {{on "click" (fn this.renew l)}}>Renew</button>
                              {{/if}}
                              <button type="button" class="el-btn el-btn--primary" disabled={{this.busy}} {{on "click" (fn this.returnLoan l)}}>Return</button>
                            </span>
                          </li>
                        {{/each}}
                      </ul>
                    {{else}}
                      <p class="el-hint">Nothing on loan.</p>
                    {{/if}}
                  </div>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}
    </section>
  </template>
}

