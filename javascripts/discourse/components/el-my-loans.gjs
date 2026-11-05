import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import store from "../lib/catalogue-store";
import auth, { dueText, formatDate, isOverdue, LibraryAuthError, renewalsLeft } from "../lib/library-api";
import { membershipLink } from "../lib/membership";

// "My loans" for anyone signed in to the forum: what they have out, when it's
// due, and a Renew button (same renewal rules as the Google app). Matched to
// their Members row by forum account, then email.

const HISTORY_LIMIT = 30;
const eqOne = (n) => n === 1;

export default class ElMyLoans extends Component {
  @service currentUser;

  @tracked loading = true;
  @tracked error = null;
  @tracked expired = false;
  @tracked member = null;
  @tracked loans = [];
  @tracked rules = null;
  @tracked busy = null;
  @tracked notice = null;
  @tracked showHistory = false;

  constructor() {
    super(...arguments);
    this.start();
  }

  async start() {
    this.loading = true;
    this.error = null;
    this.expired = false;
    const ready = await auth.ensure(this.currentUser);
    if (!ready) {
      this.loading = false;
      return;
    }
    store.ensureLoaded(settings.data_url, settings.refresh_after_minutes);
    try {
      this.apply(await auth.call("myLoans"));
    } catch (e) {
      this.handleError(e);
    } finally {
      this.loading = false;
    }
  }

  apply(r) {
    if (!r?.ok) {
      throw new Error(r?.error || "Couldn't load your loans.");
    }
    this.member = r.member;
    this.loans = r.loans || [];
    this.rules = r.settings || null;
  }

  handleError(e) {
    if (e instanceof LibraryAuthError) {
      this.expired = true;
    } else {
      this.error = e.message || String(e);
    }
  }

  @action
  signInAgain() {
    auth.restart();
    this.start();
  }

  get anonymous() {
    return !this.currentUser;
  }

  get authError() {
    return auth.status === "error" ? auth.error : null;
  }

  get firstName() {
    return String(this.member?.name || this.currentUser?.name || this.currentUser?.username || "").split(" ")[0];
  }

  get membership() {
    return membershipLink(this.currentUser);
  }

  get lapsed() {
    return this.member?.membership === "Lapsed";
  }

  decorate(l) {
    // Reading store.books ties covers to the catalogue download finishing.
    const book = store.books && store.byKey ? store.findBook({ isbn: l.isbn, title: l.title, author: "" }) : null;
    const left = renewalsLeft(l, this.rules);
    return {
      ...l,
      overdue: isOverdue(l),
      due: dueText(l),
      dueDate: formatDate(l.dueDate),
      loanDate: formatDate(l.loanDate),
      renewalsLeft: left,
      canRenew: l.status === "Active" && left > 0,
      renewing: this.busy === l.loanId,
      cover: book && book._hasCover ? book.coverUrl : null,
      author: book ? book.author : "",
    };
  }

  get current() {
    return this.loans
      .filter((l) => l.status === "Active")
      .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate))
      .map((l) => this.decorate(l));
  }

  get history() {
    return this.loans
      .filter((l) => l.status !== "Active")
      .sort((a, b) => new Date(b.loanDate) - new Date(a.loanDate))
      .slice(0, HISTORY_LIMIT)
      .map((l) => this.decorate(l));
  }

  get summary() {
    const n = this.current.length;
    const overdue = this.current.filter((l) => l.overdue).length;
    if (!n) {
      return "You don't have any books out at the moment.";
    }
    const base = `You have ${n} book${n === 1 ? "" : "s"} out`;
    return overdue ? `${base} — ${overdue} overdue. Please bring ${overdue === 1 ? "it" : "them"} back soon.` : `${base}.`;
  }

  @action
  toggleHistory() {
    this.showHistory = !this.showHistory;
  }

  @action
  async renew(loan) {
    this.busy = loan.loanId;
    this.notice = null;
    try {
      const r = await auth.call("renewMine", { loanId: loan.loanId });
      if (!r.ok) {
        this.notice = { kind: "error", text: r.error || "Couldn't renew that." };
        return;
      }
      this.apply(r);
      this.notice = { kind: "ok", text: `Renewed “${loan.title}” — now due ${formatDate(r.renewed?.newDueDate)}.` };
    } catch (e) {
      this.handleError(e);
    } finally {
      this.busy = null;
    }
  }

  @action
  dismissNotice() {
    this.notice = null;
  }

  <template>
    <section class="el-myloans" aria-labelledby="el-myloans-heading">
      <header class="el-page-head">
        <h1 id="el-myloans-heading" class="el-page-head__title">My loans</h1>
      </header>

      {{#if this.anonymous}}
        <div class="el-state">
          <p>Log in to see the books you've borrowed.</p>
          <a class="el-btn el-btn--primary" href="/login">Log in</a>
        </div>
      {{else if this.expired}}
        <div class="el-state el-state--error">
          <p>Your session has expired.</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Sign in again</button>
        </div>
      {{else if this.authError}}
        <div class="el-state el-state--error">
          <p>{{this.authError}}</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Try again</button>
        </div>
      {{else if this.error}}
        <div class="el-state el-state--error">
          <p>{{this.error}}</p>
          <button type="button" class="el-btn" {{on "click" this.signInAgain}}>Try again</button>
        </div>
      {{else if this.loading}}
        <div class="el-state"><p>Fetching your loans…</p></div>
      {{else if this.member}}
        <p class="el-myloans__hello">Hi {{this.firstName}}. {{this.summary}}</p>
        {{#if this.lapsed}}
          <p class="el-hint el-hint--warn">
            Your membership has lapsed, so you can't borrow anything new.
            <a href={{this.membership.href}}>Renew your membership</a>.
          </p>
        {{/if}}

        {{#if this.notice}}
          <div class="el-notice is-{{this.notice.kind}}" role="status">
            <span>{{this.notice.text}}</span>
            <button type="button" class="el-notice__close" aria-label="Dismiss" {{on "click" this.dismissNotice}}>✕</button>
          </div>
        {{/if}}

        {{#if this.current.length}}
          <ul class="el-myloans__grid">
            {{#each this.current as |l|}}
              <li class="el-myloan {{if l.overdue 'is-overdue'}}">
                <span class="el-myloan__cover">
                  {{#if l.cover}}<img src={{l.cover}} alt="" loading="lazy" />{{else}}<span class="el-myloan__nocover">{{l.title}}</span>{{/if}}
                </span>
                <span class="el-myloan__title">{{l.title}}</span>
                {{#if l.author}}<span class="el-myloan__author">{{l.author}}</span>{{/if}}
                <span class="el-myloan__due"><strong>{{l.due}}</strong><br />{{l.dueDate}}</span>
                {{#if l.canRenew}}
                  <button type="button" class="el-btn" disabled={{this.busy}} {{on "click" (fn this.renew l)}}>
                    {{if l.renewing "Renewing…" "Renew"}}
                  </button>
                  <span class="el-myloan__left">{{l.renewalsLeft}} renewal{{if (eqOne l.renewalsLeft) "" "s"}} left</span>
                {{else}}
                  <span class="el-myloan__left">No renewals left — please return it by the due date.</span>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}

        {{#if this.history.length}}
          <button type="button" class="el-adv-toggle {{if this.showHistory 'is-open'}}"
            aria-expanded={{if this.showHistory "true" "false"}} {{on "click" this.toggleHistory}}>
            <span class="el-adv-toggle__arrow" aria-hidden="true">▼</span>
            Borrowing history ({{this.history.length}})
          </button>
          {{#if this.showHistory}}
            <ul class="el-loanlist el-loanlist--compact">
              {{#each this.history as |l|}}
                <li class="el-loan is-returned">
                  <span class="el-loan__main">
                    <span class="el-bookrow__title">{{l.title}}</span>
                    <span class="el-loan__due">Borrowed {{l.loanDate}}</span>
                  </span>
                </li>
              {{/each}}
            </ul>
          {{/if}}
        {{/if}}
      {{else}}
        <div class="el-state">
          <p>We couldn't find a library membership for your forum account.</p>
          <p class="el-hint">
            If you've just joined, it can take a few minutes to come through, or ask a librarian at the desk.
          </p>
          <a class="el-btn el-btn--primary" href={{this.membership.href}}>{{this.membership.label}}</a>
        </div>
      {{/if}}
    </section>
  </template>
}

