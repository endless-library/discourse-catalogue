import { tracked } from "@glimmer/tracking";

// Talks to the library's Apps Script (LibraryApi.gs) for the Library Manager
// and My loans pages, and handles signing in through DiscourseConnect:
//
//   1. ask the script for a signed /session/sso_provider link ("login")
//   2. go there; Discourse sends the browser straight back to this page with
//      ?sso=…&sig=… saying who the user is (captured at boot, see
//      captureSsoReturn, before Discourse's router drops unknown params)
//   3. hand that to the script ("session"), which checks it and returns a
//      token that's good for 6 hours, kept in localStorage per forum user.
//
// Requests are POSTs with a text/plain body: that's a "simple" request, so
// the browser sends it to Apps Script without a CORS preflight, and Apps
// Script's redirected reply allows any origin.

const STORE_PREFIX = "el-lib:session:";
const REDIRECT_KEY = "el-lib:redirect-at";

let pendingReturn = null;

export class LibraryAuthError extends Error {}

// Called once at boot (api-initializer).
export function captureSsoReturn() {
  try {
    const url = new URL(window.location.href);
    const sso = url.searchParams.get("sso");
    const sig = url.searchParams.get("sig");
    if (sso && sig) {
      pendingReturn = { sso, sig };
      url.searchParams.delete("sso");
      url.searchParams.delete("sig");
      window.history.replaceState(window.history.state, "", url.pathname + url.search + url.hash);
    }
  } catch {
    // old browser without URL(): sign-in just won't complete; the page says so
  }
}

export function libraryApiUrl() {
  const base = String(settings.manager_api_url || settings.data_url || "").trim();
  return base ? `${base.split("?")[0]}?api=1` : "";
}

function readStored(username) {
  try {
    const raw = window.localStorage.getItem(STORE_PREFIX + username);
    const s = raw && JSON.parse(raw);
    if (s?.token && Date.parse(s.expiresAt) - Date.now() > 5 * 60 * 1000) {
      return s;
    }
  } catch {
    // ignore
  }
  return null;
}

function writeStored(username, value) {
  try {
    if (value) {
      window.localStorage.setItem(STORE_PREFIX + username, JSON.stringify(value));
    } else {
      window.localStorage.removeItem(STORE_PREFIX + username);
    }
  } catch {
    // private mode etc.: the session just won't outlive the page
  }
}

class LibraryAuth {
  @tracked user = null; // { username, name, librarian }
  @tracked status = "idle"; // idle | checking | redirecting | ready | anon | error
  @tracked error = null;

  token = null;
  username = null;
  inflight = null;

  // Makes sure there's a session for this forum user. Resolves true when
  // ready; false while redirecting to sign in, for anonymous visitors, or on
  // error (see .status / .error).
  ensure(currentUser) {
    if (!currentUser) {
      this.status = "anon";
      return Promise.resolve(false);
    }
    if (this.username !== currentUser.username) {
      this.token = null;
      this.user = null;
      this.username = currentUser.username;
    }
    if (this.token) {
      return Promise.resolve(true);
    }
    if (!this.inflight) {
      this.inflight = this._ensure().finally(() => (this.inflight = null));
    }
    return this.inflight;
  }

  async _ensure() {
    this.error = null;
    const stored = readStored(this.username);
    if (stored) {
      this.token = stored.token;
      this.user = stored.user;
      this.status = "ready";
      return true;
    }

    this.status = "checking";
    try {
      if (pendingReturn) {
        const { sso, sig } = pendingReturn;
        pendingReturn = null;
        const r = await this.post({ action: "session", sso, sig });
        if (r.ok) {
          this.token = r.token;
          this.user = r.user;
          writeStored(this.username, { token: r.token, expiresAt: r.expiresAt, user: r.user });
          this.status = "ready";
          return true;
        }
        this.fail(r.error || "Sign-in didn't complete.");
        return false;
      }

      // Don't bounce back and forth if something's wrong with the setup.
      let last = 0;
      try {
        last = Number(window.sessionStorage.getItem(REDIRECT_KEY)) || 0;
      } catch {
        // ignore
      }
      if (Date.now() - last < 30 * 1000) {
        this.fail("Sign-in didn't complete. Check the DiscourseConnect settings, then try again.");
        return false;
      }

      const returnUrl = window.location.origin + window.location.pathname;
      const r = await this.post({ action: "login", returnUrl });
      if (!r.ok || !r.url) {
        this.fail(r.error || "Couldn't start sign-in.");
        return false;
      }
      try {
        window.sessionStorage.setItem(REDIRECT_KEY, String(Date.now()));
      } catch {
        // ignore
      }
      this.status = "redirecting";
      window.location.assign(r.url);
      return false;
    } catch (e) {
      this.fail(e.message || String(e));
      return false;
    }
  }

  fail(message) {
    this.error = message;
    this.status = "error";
  }

  // Clears the saved session and signs in again (goes via the forum).
  restart() {
    writeStored(this.username, null);
    try {
      window.sessionStorage.removeItem(REDIRECT_KEY);
    } catch {
      // ignore
    }
    this.token = null;
    this.user = null;
    this.status = "idle";
    this.inflight = null;
  }

  async post(body) {
    const url = libraryApiUrl();
    if (!url) {
      throw new Error("No library server address is set in the theme settings.");
    }
    let response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "text/plain;charset=utf-8" },
        body: JSON.stringify(body),
        credentials: "omit",
        redirect: "follow",
      });
    } catch {
      throw new Error("Couldn't reach the library server. Check your connection and try again.");
    }
    if (!response.ok) {
      throw new Error(`The library server answered with HTTP ${response.status}.`);
    }
    try {
      return await response.json();
    } catch {
      throw new Error(
        "The library server sent something unexpected. Is the new version deployed (Execute as: Me, Anyone)?"
      );
    }
  }

  // An authenticated call. Throws LibraryAuthError when the session has
  // expired (the page then offers "Sign in again").
  async call(action, data = {}) {
    const r = await this.post({ ...data, action, token: this.token });
    if (r && r.code === "auth") {
      writeStored(this.username, null);
      this.token = null;
      throw new LibraryAuthError(r.error || "Your session has expired.");
    }
    return r;
  }
}

export default new LibraryAuth();

// ── Formatting shared by both pages ─────────────────────────────────────────

const DAY = 864e5;

function startOfDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function formatDate(value) {
  const d = new Date(value);
  return isNaN(d) ? "" : d.toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" });
}

export function daysUntil(value) {
  const d = new Date(value);
  return isNaN(d) ? null : Math.round((startOfDay(d) - startOfDay(new Date())) / DAY);
}

export function isOverdue(loan) {
  return loan.status === "Active" && new Date(loan.dueDate) < new Date();
}

export function dueText(loan) {
  if (loan.status !== "Active") {
    return "Returned";
  }
  const n = daysUntil(loan.dueDate);
  if (n === null) {
    return "";
  }
  if (n < 0) {
    return `${-n} day${n === -1 ? "" : "s"} overdue`;
  }
  if (n === 0) {
    return "Due today";
  }
  if (n === 1) {
    return "Due tomorrow";
  }
  return `Due in ${n} days`;
}

export function renewalsLeft(loan, defaults) {
  const max = loan.maxRenewals ?? defaults?.maxRenewals ?? 0;
  return Math.max(0, max - (loan.renewCount || 0));
}

// Same "is this book out?" key as loanBooks() in Code.gs.
export function loanKey(isbn, title, collection) {
  const i = String(isbn || "").trim();
  return i ? `i:${i}` : `t:${String(title || "").trim()}|${String(collection || "").trim()}`;
}
