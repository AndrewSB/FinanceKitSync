# v1.1 — subscription

**Goal:** 3-day free trial on first launch, then $2.99/month auto-renewing.

**Status:** **app side built** (2026-08-06), following the two recommendations
below — grandfather pre-paywall installs, gate background sync only. What is
left is everything that isn't code: the App Store Connect product, the sandbox
pass, and the grandfathering device test. See **[Where this stands](#where-this-stands)**
at the bottom.

---

## The decision that has to come first

**Do v1.0 users keep the app for free?**

v1.0 ships free with no paywall. Everyone who installs it before v1.1 has a
working app. When v1.1 lands, they update into a paywall — and the thing that
stops working is a *background* sync they set up once and stopped thinking
about. They will not notice it stopped. They will notice weeks later that their
data is stale.

Three options:

| | |
|---|---|
| **Grandfather them** *(recommended)* | Record, on first v1.1 launch, whether this install predates the paywall. If so, entitle it permanently. Costs you nothing today — v1.0 has no users yet — and it is the difference between "they added a subscription" and "they took away what I already had". |
| Trial applies to everyone | Existing users get 3 days from the v1.1 update, then pay. Simplest code. Worst experience for the small number of people who backed you first. |
| Hard cutover | Everyone pays immediately. Don't. |

Grandfathering is cheap **only if you build it now**: it needs a flag written on
first launch of v1.1, and once someone has updated, the information about
whether they predated the paywall is gone. There is no retroactive fix.

`AppTransaction.originalAppVersion` (StoreKit 2) gives you this for free — it
reports the app version originally purchased/downloaded, and it is signed by
Apple, so it can't be spoofed by reinstalling. Compare against the first
paywalled build number.

## What gets gated

Also a decision, and it shapes everything else.

The app does one thing. If syncing is gated, an unsubscribed app is inert — it
shows a paywall and nothing else. That is honest but stark, and it means an
expired subscriber's data silently goes stale, which is the same failure mode as
above.

**Recommendation:** gate **background sync**, leave **manual sync** working.

- Subscribers: background refresh, so it keeps up without being opened. That's
  the actual product — "set it and forget it."
- Lapsed/free: the app still works, but only when opened and pulled to refresh.
- Nothing already delivered is taken away, and the local ledger is never cleared
  on expiry.

This makes the subscription buy *convenience*, which is defensible, rather than
access to the user's own financial data, which is not a good look for an app
whose entire pitch is data ownership. It also keeps a lapsed user from
discovering the lapse through silent data loss.

Whatever you choose, the expiry behaviour must be **loud** — a banner on Home,
not a silent no-op in a BGTask.

## App Store Connect setup

1. **Subscription group** — one, e.g. "FinanceKit Sync". Groups exist so users
   can move between tiers; one tier today, but the group is required.
2. **Subscription product** — product ID `com.asb.FinanceKitSync.monthly`,
   1 month, $2.99 (USA base), all territories.
3. **Introductory offer** — type **Free Trial**, duration **3 days**, all
   territories. This is what makes the trial automatic: StoreKit applies it at
   purchase for anyone eligible, with no code branching on your side.
4. **Localized display name + description**, and a **review screenshot** of the
   paywall — required, and a common cause of "Missing Metadata".
5. **Terms of Use (EULA)** — auto-renewables require it. Apple's standard EULA
   is fine; link it from the paywall alongside the existing privacy policy.

Most of this is API-automatable (`/v1/subscriptionGroups`,
`/v1/subscriptions`, `/v1/subscriptionIntroductoryOffers`), so it can live in
`tools/` like the listing does. The review screenshot upload is the same
reserve → PUT → commit dance as `push_screenshots.py`.

> **Eligibility is Apple's to decide, not yours.** A user who has already had
> the trial — on this Apple ID, on any device — is not eligible again. Never
> hardcode "3 days" in the UI; read the offer off `Product.subscription` and
> check `isEligibleForIntroOffer`. Showing "3 days free" to someone who won't
> get it is a rejection under 3.1.2 and, worse, a lie in your own paywall.

## In the app

Nothing here needs a server, which fits the project: StoreKit 2 transactions are
signed by Apple and verified on device. No receipt-validation backend, no App
Store Server Notifications, no new infrastructure. Keep it that way.

### New

| File | |
|---|---|
| `Purchases/SubscriptionStore.swift` | `@Observable`, `@MainActor`. Loads the product, exposes `isEntitled`, purchases, restores, and listens to `Transaction.updates` for renewals, refunds, and revocations. |
| `Purchases/Entitlement.swift` | The single answer to "may this install sync in the background?" — subscription OR grandfathered. Nothing else in the app should reason about receipts. |
| `Views/PaywallView.swift` | Price, trial length, renewal terms, restore, EULA + privacy links. |
| `FinanceKitSync.storekit` | Local StoreKit configuration, so the paywall can be tested in the simulator without sandbox accounts. |

### Changed

- `SyncCoordinator.scheduleBackgroundRefresh()` — refuse to schedule when not
  entitled, and cancel any pending request on expiry.
- The BGTask handler — re-check entitlement at execution time, not just at
  scheduling time. A subscription can lapse between the two.
- `HomeView` — a visible state for "background sync is off because the
  subscription lapsed", with the manual path still working.
- `SettingsView` — subscription status, manage link
  (`showManageSubscriptions`), restore purchases.

### Verify entitlement in exactly one place

`Transaction.currentEntitlements` is the source of truth. Read it in
`Entitlement`, nowhere else. The failure mode to avoid is entitlement checks
sprinkled across views that disagree with each other — particularly on launch,
before StoreKit has finished loading, when the honest answer is "don't know yet"
rather than "not entitled". Model that third state explicitly; a paywall that
flashes in front of a paying subscriber on every cold start is a support ticket
and a 1-star review.

## Testing

- **StoreKit configuration file** for the fast loop: purchase, renew, expire,
  refund, and *trial-ineligible* — that last one is the path most likely to be
  broken, because it's the one you never see while developing.
- **Sandbox** for the real thing, including "already used the trial".
- **Grandfathering** needs a device that installed v1.0 first. Do this before
  v1.1 ships; it cannot be tested retroactively.
- Existing 44 tests must keep passing. `Entitlement` should be injectable so
  sync tests don't need StoreKit at all.

## Review notes for v1.1

Add to the existing notes (`app-store.md` §4):

> The app offers a 3-day free trial, then a $2.99/month auto-renewing
> subscription. The subscription enables automatic background syncing. Manual
> sync remains available without a subscription, and no previously synced data
> is ever withheld.

Reviewers test in sandbox, where the trial is honoured. Expect scrutiny of the
paywall's disclosure under 3.1.2 — price, period, auto-renewal, and how to
cancel must all be visible on the paywall itself, not behind a link.

## Sequence

1. Decide grandfathering and what's gated. **Everything else depends on these.**
2. App Store Connect: group, product, intro offer, EULA link.
3. `SubscriptionStore` + `Entitlement`, with tests.
4. Gate background sync; make expiry loud.
5. Paywall.
6. StoreKit-config tests, then sandbox.
7. Screenshots — the paywall likely deserves one, which means re-running
   `tools/screenshots.sh` with a new scene.
8. Version 1.1, build via Xcode Cloud `Release`, submit.

## Worth saying once

This app charges $2.99/month to move the user's own data to a server the user
already pays for and runs themselves. That's a coherent product — you're selling
the FinanceKit entitlement and the maintenance behind it, which nobody else can
easily offer. But the audience is self-hosters, who are unusually price-sensitive
about subscriptions for software that has no ongoing cost to serve.

A one-time purchase would fit the product's shape better and is worth
considering. This is your call, and the plan above implements the subscription
as asked either way — the only part that would change is the App Store Connect
product type.

---

## Where this stands

Built 2026-08-06, on the plan above. Both open decisions were taken as
recommended: **grandfather** pre-paywall installs, gate **background sync only**.

### In the app

| | |
|---|---|
| `Purchases/Entitlement.swift` | The single source of truth. Three states — `.unknown`, `.entitled(.subscription/.grandfathered)`, `.notEntitled`. `Transaction.currentEntitlements` is read here and nowhere else. |
| `Purchases/SubscriptionStore.swift` | Product load, purchase, restore, `Transaction.updates`. Exposes an `Offer` (price, period, trial) read off StoreKit — the trial line only appears when Apple says this Apple ID is eligible. |
| `Views/PaywallView.swift` | Price, period, renewal terms and how to cancel, all on the screen itself (3.1.2). Restore, EULA and privacy links. |
| `FinanceKitSync.storekit` | Local StoreKit configuration, wired into the scheme's Run **and** Test actions. |
| `SyncCoordinator` | `backgroundRefreshAction(entitlement:backgroundSyncEnabled:isConfigured:)` — a pure function returning `.schedule` / `.leaveAsIs` / `.cancel`. The BGTask handler re-checks entitlement at execution time and does not reschedule when it's gone. |
| `HomeView` | A loud "Background sync is off" section on lapse, with the manual path untouched. |
| `SettingsView` | Status, manage subscription, restore, and a paywall entry on the gated toggle. |

Ten tests were added; the suite is **54 and green**. None of them touch
StoreKit: `Entitlement.fixed(_:)` and the pure gating function are the seams.

**`.unknown` is the load-bearing state.** It never permits background sync and
never cancels a pending refresh — so a cold start can't flash a paywall at a
subscriber, and can't quietly drop their scheduled sync while StoreKit is still
answering.

**Grandfathering is decided once and cached.** `AppTransaction.originalAppVersion`
is compared against `Entitlement.firstPaywalledBuild` (**20** — v1.0 shipped as
build 19). An unparseable version, which is what StoreKit testing and TestFlight
report, counts as *not* grandfathered: asking a developer to subscribe is the
harmless direction to be wrong in.

### App Store Connect

`tools/push_subscription.py` + `tools/subscription.json` do the group, product,
price, localization, free trial, availability, and review screenshot — dry-run
by default, same shape as `push_listing.py`.

> ⚠️ **Written but never run.** It has not been executed against the live
> account, so treat its first `--apply` as the test. Run it dry first, and
> expect the Paid Applications agreement to need signing before any in-app
> purchase endpoint answers at all.

### Still to do

1. Sign the **Paid Applications agreement** — nothing else works until it is.
2. `python3 tools/push_subscription.py` (dry), then `--apply`.
3. `./tools/screenshots.sh` — it now captures a sixth `paywall` scene, which
   doubles as the subscription's required review screenshot.
4. **Sandbox pass**, including the trial-ineligible path.
5. **Grandfathering device test** — install v1.0 first, then update. This one
   cannot be done retroactively.
6. Bump `MARKETING_VERSION` to 1.1, add the review note below, submit.

Add to the review notes (`app-store.md` §4):

> The app offers a 3-day free trial, then a $2.99/month auto-renewing
> subscription. The subscription enables automatic background syncing. Manual
> sync remains available without a subscription, and no previously synced data
> is ever withheld.
