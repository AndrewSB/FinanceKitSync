# App Store submission

Everything needed to submit, in the order it has to happen. **You** perform the
account actions — I don't have and shouldn't have access to your Apple account.

---

## ⚠️ Step 0 — Eligibility. Read this before writing any more code.

Apple publishes explicit criteria for the FinanceKit entitlement, and **the app
as currently specified does not meet all of them.** Verified against
<https://developer.apple.com/financekit/> on 2026-08-04.

| Apple's criterion | FinanceKitSync today | |
|---|---|---|
| Request submitted by the **Account Holder** of the developer account | Andrew is the Account Holder of `A29347X2JZ` | ✅ |
| Held under an **organization-level** account (per Apple's guidance and developer-forum reports) | `A29347X2JZ` is registered as "Andrew Breckenridge" — very likely an **Individual** account | ❓ **verify** |
| Listed in the **Finance category** in App Store Connect | Planned as Finance | ✅ |
| Distributed through the **App Store for iPhone in the US or UK** | Planned | ✅ |
| **"Provide financial management tools (for example, a comprehensive view of net worth, spending trends, budgeting)"** | SPEC §1 explicitly rules these out: *"No budgeting, categorization, charts, or analytics in the app."* | ❌ **conflict** |

### The problem

FinanceKitSync is deliberately a pure data-export utility — it reads
transactions and forwards them, and does nothing else. That is exactly what
Apple's last criterion excludes. An app whose entire pitch is "we don't analyze
your data, we just move it" is a poor fit for a criterion that asks for net
worth views, spending trends, and budgeting.

This is a product-level risk, not a paperwork one. It cannot be fixed by
wording the request more carefully.

### Options

1. **Add a genuine financial-management surface to the app** *(recommended)*.
   The app already reads every account balance and the full transaction
   history — the data for a net-worth total, per-account balances, and a
   spending-trend view is *already in memory* during a sync and currently
   thrown away. Building an in-app Accounts tab and a simple monthly
   spending-by-category view is a modest addition that turns a ❌ into a ✅,
   and makes the app more useful on its own terms. Syncing to your own server
   then becomes a headline feature rather than the only feature.

2. **Submit as-is and argue the case.** Faster, but the criterion is stated
   plainly and the app visibly doesn't meet it. Expect rejection.

3. **Ship without the App Store.** A personal/dev build works on a registered
   device — but note that even a development build needs the entitlement, so
   this only works if Apple grants it, which lands back at option 1.

**Recommendation: option 1.** It is a few days of work, it addresses the only
hard blocker, and it doesn't compromise the privacy story at all — the analysis
happens on-device, on data the app already holds.

### Also verify before filing

**Is `A29347X2JZ` an Individual or Organization account?** Check at
<https://developer.apple.com/account> → Membership. If it's Individual and
Apple requires Organization, converting needs a **D-U-N-S number** and takes
one to several weeks — which would become the new critical path, ahead of
everything else. This is the single highest-value thing to check right now.

## Step 0b — Submitting the request

**Where:** <https://developer.apple.com/contact/request/financekit>

**Team ID:** `A29347X2JZ`
**Bundle ID:** `com.asb.FinanceKitSync` *(already registered — Xcode created it
during a provisioning run on 2026-08-04)*

Entitlements are granted **per bundle ID**, and can only be used with the
single binary associated with that bundle ID.

### Draft request text

> FinanceKitSync is a personal-data-portability utility. It reads the user's
> Apple Card, Apple Cash, and Apple Pay transaction history via FinanceKit and
> transmits it, over TLS, to a server address that the user themselves supplies
> and operates.
>
> There is no backend operated by us. The app has no accounts, no analytics, and
> no third-party SDKs. The only network destination is the URL the user enters
> during setup, authenticated with a bearer token they also supply. Transaction
> data is never sent anywhere else and is never retained on our infrastructure,
> because we do not have any.
>
> On the device, the app stores only bookkeeping: for each transaction it has
> already delivered, a FinanceKit identifier, a SHA-256 content hash used to
> detect corrections, and a timestamp. No amounts, merchants, or dates are
> persisted locally.
>
> We request the `financial-data` capability because reading the user's
> transaction history is the app's entire function. Users commonly want their
> own spending data in their own database, spreadsheet, or budgeting tool, and
> FinanceKit is the only supported way to obtain it on iOS.
>
> This capability is already approved for a related app, LunchSync
> (`com.littlebluebug.AppleCardSync`, team MF7QJ9TF5S), which syncs the same
> data to one specific budgeting service. FinanceKitSync is the generalized
> version, published under a different team by agreement with that app's owner.

Adjust the last paragraph if the relationship is better left unmentioned —
it's offered because Apple sometimes asks how a request relates to an existing
approved app, and volunteering it is usually better than being asked.

> **If Apple asks for a demo build:** they occasionally do for financial-data
> requests. TestFlight is the easiest delivery, which means the `Release`
> workflow needs to have run at least once — but that workflow needs the
> entitlement. If this happens, reply asking whether an unentitled build plus a
> screen recording will do; that combination has satisfied similar requests.

---

## Step 1 — Decide the display name

The bundle ID and repo name can stay `FinanceKitSync`. The **App Store display
name** probably should not: App Review guideline 4.1 and Apple's trademark
guidance both discourage app names built from Apple technology names, and
"FinanceKit" is one. This is a cheap thing to get right up front and an annoying
one to fix mid-review.

Candidates, in rough order of preference:

| Name | Note |
|---|---|
| **Ledgerline** | No conflict, reads like a product, leaves room to grow |
| **Card Mirror** | Describes the function; "mirror" is already the project's vocabulary |
| **Transaction Export** | Maximally literal, poor differentiation |

Subtitle (30 char limit): `Your transactions, your server`

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
> and presents balances, net worth, and spending trends on device. It also lets
> the user mirror that data to a personal server address they configure — there
> is no hosted backend, and no data reaches us.
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

> **Before submitting:** stand up a throwaway server for this, with its own
> token, containing only synthetic data. Do not give App Review the token to
> `box`. `server/deploy.sh` will spin up a second instance on any host.

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

- [ ] FinanceKit entitlement requested *(step 0 — do this today)*
- [ ] Entitlement approved
- [ ] `FKS_UNENTITLED` removed from all Xcode Cloud workflows
- [ ] Display name decided and set
- [ ] Landing page live, URL in App Store Connect
- [ ] Throwaway review server running with synthetic data
- [ ] Privacy labels completed
- [ ] Screenshots captured from synthetic data
- [ ] `Release` workflow run, build in TestFlight
- [ ] Internal TestFlight pass on a real device with real transactions
- [ ] Submit

---

## What I can and can't do here

I can: write and maintain everything above, build and sign locally, run the
Xcode Cloud scripts, and prepare screenshots.

I can't and won't: sign into your Apple account, file the entitlement request,
accept Apple's agreements, or press Submit. Those need your credentials and
your consent, and they're yours to make.
