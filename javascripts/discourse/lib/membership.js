// Membership link: "New membership" for non-members, "My membership" for
// members. Membership = being in the group the subscriptions plugin adds
// paying subscribers to (theme setting `membership_group`). currentUser.groups
// lists the groups the user can see themselves in, so this needs no request.

export function isMember(currentUser) {
  const wanted = String(settings.membership_group || "")
    .trim()
    .toLowerCase();
  if (!currentUser || !wanted) {
    return false;
  }
  return (currentUser.groups || []).some(
    (g) => String(g.name || "").toLowerCase() === wanted
  );
}

export function membershipLink(currentUser) {
  if (isMember(currentUser)) {
    return {
      member: true,
      label: settings.my_membership_label,
      href: `/u/${encodeURIComponent(currentUser.username)}/billing/subscriptions`,
    };
  }
  return {
    member: false,
    label: settings.new_membership_label,
    href: settings.new_membership_url || "/s",
  };
}

// True on the subscriptions plugin's pages (/s…) and the user's billing pages,
// so the header link can show as the current page.
export function onMembershipPage(path) {
  return (
    path === "/s" ||
    path.startsWith("/s/") ||
    /^\/u\/[^/]+\/billing(\/|$)/.test(path)
  );
}
