# App Store submission

Everything needed to submit, in the order it has to happen.

> **1.0 is submitted** — build 25, `WAITING_FOR_REVIEW`. This document is now
> mostly a record of how it got there and what is still owed. For the mechanics
> of producing and submitting a build, see [`releasing.md`](./releasing.md); for
> current state, [`STATUS.md`](./STATUS.md).

---

## ✅ Step 0 — Eligibility. Resolved.

The FinanceKit entitlement was **requested 2026-08-04 and approved 2026-08-06**
(`453VPT726K`, bundle `com.asb.FinanceKitSync`, team `A29347X2JZ`). Nothing in
this step remains to be done; it is kept only because two predictions made here
were wrong in ways worth remembering.

| Apple's criterion | How it actually went |
|---|---|
| Request submitted by the **Account Holder** | ✅ as expected |
| Held under an **organization-level** account | ✅ **approved on an Individual account.** The requirement appears in the FinanceKit API docs but is not enforced at request time. This file rated it the single largest risk. It wasn't one. |
| Listed in the **Finance category**, US App Store | ✅ as expected |
| **"Provide financial management tools"** (net worth, spending trends, budgeting) | ✅ **approved without any of them.** This app is a pure export tool and says so. |

The plan this document once recommended — building an Accounts + Trends surface
*in order to qualify* — is **withdrawn**. It was reasoned from Apple's published
criteria, which read as hard requirements and are not applied that way.
LunchSync (<https://apps.apple.com/us/app/lunch-sync/id6739702427>) holds the
same entitlement as a pure sync tool with no analysis features at all. Build
those screens on product merit or not at all.

**What actually cost time was the step after approval**, which nothing here
anticipated: being granted the entitlement does not enable the capability on the
App ID, and automatic signing keeps minting profiles without it, failing with an
identical error every time. See [`STATUS.md`](./STATUS.md).

## Step 0b — Submitting the request — done

Filed 2026-08-04 at <https://developer.apple.com/contact/request/financekit>
for team `A29347X2JZ` / bundle `com.asb.FinanceKitSync`, using the "Version B"
text (the app as it is, with no financial-management features). Approved
2026-08-06. The full drafts are archived in
[`archive/entitlement-request-text.md`](./archive/entitlement-request-text.md).

Entitlements are granted **per bundle ID** and only work with the single binary
associated with it — worth remembering if a second app ever needs one.

Apple did not ask for a demo build, which had been a worry: the `Release`
workflow could not run without the entitlement it was being asked to prove.

---

## Step 1 — Display name — decided

**"FinanceKit Sync"**, set on the App Store Connect record and currently in
review under that name. Subtitle: `Your transactions, your server`.

This went against the advice this section used to give. App Review guideline
4.1 and Apple's trademark guidance both discourage names built from Apple
technology names, and alternatives were drafted (*Ledgerline*, *Card Mirror*,
*Transaction Export*). The risk was accepted deliberately on 2026-08-04:
"FinanceKit" is absent from Apple's published trademark list while every sibling
framework is registered, and the worst case is a metadata rejection fixable the
same day without a new binary. See [`listing.md`](./listing.md).

Still unresolved, and cosmetic: the app itself has no `CFBundleDisplayName`, so
the Home Screen icon and `HomeView` title both read "FinanceKitSync" while the
store says "FinanceKit Sync".

---

## Step 2 — App Store Connect record

| Field | Value |
|---|---|
| Primary category | Finance |
| Secondary category | Utilities |
| Age rating | 4+ |
| Price | *(your call — free, or one-time paid)* |
| Availability | All territories |

### Description

> Your Apple Card, Apple Cash, and Apple Pay transactions belong to you. This
> app puts them where you can actually use them.
>
> Point it at a server you run, and it copies your transaction history there —
> the full history, not just the last month — and keeps it current as new
> charges post. What you build on top of that is up to you: a database, a
> spreadsheet, a budgeting tool, a dashboard, an archive.
>
> HOW IT WORKS
> • Your transactions are read on your iPhone, using Apple's FinanceKit.
> • They're sent over an encrypted connection to the address you enter.
> • Nothing goes anywhere else. There is no account and no service in between.
>
> WHAT'S SENT
> Every field Apple exposes: amount, currency, date, posted date, merchant name
> and category code, transaction type, pending or posted status, and foreign
> currency amounts and exchange rates where applicable.
>
> WHAT'S STORED ON YOUR PHONE
> Only a record of what has already been delivered — an identifier and a
> checksum per transaction. No amounts. No merchants.
>
> YOU NEED YOUR OWN SERVER
> This app does not come with one, and there's no hosted option. The setup guide
> covers running the open-source receiver on any machine you control. If you
> don't want to run a server, this app isn't for you.
>
> Open source: github.com/AndrewSB/FinanceKitSync

### Keywords (100 char limit)

```
apple card,export,transactions,self-hosted,finance,csv,sync,backup,privacy,financekit,budget,api
```

### Support & marketing URLs

Both point at the landing page — see [`workstream-landing.md`](./workstream-landing.md).

---

## Step 3 — Privacy nutrition labels

> **Web UI only — there is no API for this.** Checked against the live API on
> 2026-08-06: `apps` exposes no privacy or data-usage relationship, and
> `/v1/appDataUsages`, `/v1/appDataUsageCategories`, and
> `appDataUsagesPublishState` all 404. Unlike the listing metadata, this one
> genuinely cannot be scripted — it's four clicks in App Store Connect:
>
> **App Store Connect → FinanceKit Sync → App Privacy → Get Started →** answer
> **"No"** to *Do you or your third-party partners collect data from this app?*
> → **Publish**.

This is the section most likely to trip you up, because the honest answer is
unusual. Work through it as: *does the developer collect this?*

| Question | Answer |
|---|---|
| Does your app collect data? | **No** |

That single answer is correct and sufficient. Apple defines "collect" as
transmitting data off-device **to the developer or a third party the developer
engages**. Here, data goes only to a destination the *user* chooses and
operates. Apple's own documentation carves this out.

If the form pushes back or you'd rather be conservative, the alternative is to
declare **Financial Info → Other Financial Info**, with:
- Linked to identity: **No**
- Used for tracking: **No**
- Purpose: **App Functionality**

Either answer survives review. Do **not** declare tracking or advertising —
neither exists in this app.

### App Privacy details for review

Attach this as a note:

> The app contains no analytics, no advertising, no crash reporting, and no
> third-party SDKs of any kind. The only outbound network request is to the
> server address the user enters during setup.

---

## Step 4 — Review notes

Paste into "Notes for Review". Reviewers cannot test this app without a server,
so give them one.

> This app reads the user's Apple Card, Apple Cash, and Apple Pay transactions
> via FinanceKit and mirrors them to a personal server address the user
> configures. There is no hosted backend, no account, and no data reaches us.
>
> To review the sync feature end to end you'll need a test endpoint.
>
> Test server URL: __________________________
> Bearer token:    __________________________
>
> Enter both on the "Connect your server" screen during onboarding, tap "Test
> connection" (it should report Connected), then continue and allow access to
> financial data when iOS asks. On the main screen, tap "Sync now".
>
> On a device with no Apple Card or Apple Pay transaction history, the sync will
> report zero transactions and succeed — this is correct behavior, not an error.
>
> The full server source is at github.com/AndrewSB/FinanceKitSync under
> `server/`, and is about 200 lines.

> **Two corrections to the text above, both made 2026-08-06.**
>
> It previously claimed the app *"presents balances, net worth, and spending
> trends on device."* **It does not** — none of those screens exist. That
> sentence was drafted back when the plan was to build a financial-management
> surface in order to qualify for the entitlement, a plan since withdrawn (see
> step 0). Telling App Review the app does something it visibly doesn't is a
> rejection waiting to happen, so it now describes the app as built.
>
> The note below also said `server/deploy.sh` "will spin up a second instance on
> any host." It won't, as written — see the gap listed under it.

### The throwaway review server

**Before submitting:** stand up a separate server for this, with its own token,
containing only synthetic data. Do not give App Review the token to `box`.

**This is not yet done, and it is not a one-liner.** `deploy.sh` is
parameterized by `FKS_HOST`, `FKS_REMOTE_DIR`, and `FKS_FUNNEL_PORT`, but three
things are hardcoded and would collide with the live instance:

| | |
|---|---|
| `LOCAL_PORT=8501` | `deploy.sh`, and the published port in `docker-compose.yml` |
| `container_name: financekitsync` | `docker-compose.yml` — Docker refuses a second container with the same name |
| `image: financekitsync:latest` | shared, so a rebuild for one instance silently swaps the other's image |

So a second instance needs those three parameterized first — roughly a
30-line change to `docker-compose.yml` and `deploy.sh` — or a second host.

It also needs **Funnel**, because App Review is not on the tailnet. Read the
warning in `deploy.sh` before enabling it: Funnel is per-port, not per-path,
and turning it on for a port publishes every route on that port. Use a port
that serves nothing else. The 2026-08-04 incident in
[`STATUS.md`](./STATUS.md) is what happens otherwise.

Finally it needs synthetic contents: the reviewer's device will have no Apple
Card history, so a sync there reports zero transactions and the database stays
empty. Seed it by POSTing a handful of invented packets to
`/financekit-sync` with the review token before submitting.

---

## Step 5 — Screenshots

Required: 6.9" (iPhone 17 Pro Max) and 6.5". Five screens, in order:

1. Onboarding "Your transactions, on your server"
2. The connect screen, showing a successful connection test
3. Home, with a real sync in progress
4. Home, settled — last sync time and transaction count
5. Settings, showing there's nothing to configure but the server

Generate on simulator with the real UI. **Use synthetic data** — do not
screenshot your own transaction history.

---

## Submission checklist

- [x] FinanceKit entitlement requested — 2026-08-04
- [x] Entitlement approved — 2026-08-06 — **and enabled on the App ID**, which
      is a separate manual step
- [x] `FKS_UNENTITLED` removed from all Xcode Cloud workflows — verified, set
      nowhere
- [x] Display name decided and set — "FinanceKit Sync"
- [x] Landing page live, URL in App Store Connect
- [x] Privacy labels completed
- [x] Screenshots captured from synthetic data — 2 sets × 5, all `COMPLETE`
- [x] `Release` workflow run, build uploaded
- [x] Submit — build 25, submission `f3daf509-…`
- [ ] **Throwaway review server running with synthetic data** — not done, by
      decision. See below; it is the most likely cause of a 2.1 rejection.
- [x] **Pass on a real device with real transactions** — 2026-08-07. Confirmed
      by Andrew on hardware. It went unrun long enough to let a build that could
      not request the Wallet permission reach App Review; the itemised bulk-sync
      checks in [`device-test.md`](./device-test.md) are still worth working
      through.

---

## What I can and can't do here

I can: write and maintain everything above, build and sign locally, run the
Xcode Cloud scripts, and prepare screenshots.

I can't and won't: sign into your Apple account, file the entitlement request,
accept Apple's agreements, or press Submit. Those need your credentials and
your consent, and they're yours to make.
