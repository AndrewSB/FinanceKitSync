# App Store Connect setup

Click-by-click for creating the app record and listing. Everything here needs
your Apple account, so it's yours to do — but every value you'll be asked for is
written out below, so it should be copy-and-paste rather than decision-making.

> ## ⛔ Do not start this yet — 2026-08-04
>
> The account (`A29347X2JZ`) is confirmed **Individual**, and Apple's FinanceKit
> API documentation says the entitlement requires an **organization-level**
> account. Until Apple Developer Support confirms the path (see
> [`STATUS.md`](./STATUS.md)), creating the app record here may be wasted work:
> if a new organization enrolment is required, that's a different Team ID and
> this record would need transferring or recreating.
>
> Everything below stays accurate — just don't run it until the account question
> is settled.

---

## Do I submit the app first, or just the entitlement?

**Just the entitlement. Do not submit the app first — you can't.**

Without the entitlement, the binary won't even build: signing fails with
*"Entitlement com.apple.developer.financekit requires approval from Apple."*
So there is no archive to submit. The entitlement is granted per bundle ID
precisely so that you can *then* produce the build you eventually submit.

What confuses this is Apple's wording — the criteria say your app must be
*"listed in the Finance category in App Store Connect and distributed through
the App Store for iPhone in the United States or United Kingdom."* Read
literally that's circular. In practice it describes **intended** distribution:
Apple grants the entitlement so you can build, and verifies the rest at App
Review.

What that means concretely: you need the **App Store Connect app record to
exist**, with Finance as the primary category and US (and/or UK) availability
set — but you do **not** need a shipped app, an approved review, an uploaded
build, or screenshots.

> Honest caveat: the request form is behind an Apple login, so I haven't seen
> its fields. The ordering above is inferred from the constraints (you cannot
> build without the entitlement) rather than stated outright by Apple. If the
> form asks for something unexpected, that's worth recording here.

## Order of operations

```
1. Confirm membership type + tier          (5 min)   ← do this first
2. Create the app record                   (10 min)
3. Fill in the listing                     (30 min)
4. File the FinanceKit entitlement request (15 min)  ← needs 2 and 3
5. …wait, days to weeks…
6. Xcode Cloud grant + first build         (15 min)  ← can be done during the wait
7. Screenshots, privacy labels, submit
```

Steps 2, 3, and 6 can all happen while the entitlement is pending. Only the
build-and-submit part is truly blocked.

---

## 1. Confirm the account

<https://developer.apple.com/account> → **Membership details**

Record these:

| | |
|---|---|
| Team ID | should be `A29347X2JZ` |
| Entity type | **Individual** or **Organization** ← the one that matters |
| Membership status | must be Active |

If it says Individual and Apple requires Organization for FinanceKit,
**stop here** and start the conversion — it needs a D-U-N-S number and takes
one to several weeks, which makes it the critical path.

## 2. Create the app record

<https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | *see the naming caveat in [`app-store.md`](./app-store.md) §1 — probably not "FinanceKitSync"* |
| Primary language | English (U.S.) |
| Bundle ID | `com.asb.FinanceKitSync` *(already registered; it'll be in the dropdown)* |
| SKU | `financekitsync-001` *(internal only, never shown)* |
| User Access | Full Access |

Then **App Information**:

| Field | Value |
|---|---|
| Primary category | **Finance** ← required by the FinanceKit criteria, not optional |
| Secondary category | Utilities |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ (no objectionable content in any category) |

And **Pricing and Availability**:

| Field | Value |
|---|---|
| Price | Free *(or your choice)* |
| Availability | At minimum **United States** — FinanceKit is US/UK only |

## 3. Fill in the listing

Under the **1.0 Prepare for Submission** version. Copy from
[`app-store.md`](./app-store.md) §2, which has the description, keywords, and
subtitle already written.

| Field | Where it comes from |
|---|---|
| Subtitle | `app-store.md` §2 |
| Description | `app-store.md` §2 |
| Keywords | `app-store.md` §2 |
| Support URL | the landing page — needs the repo public first |
| Marketing URL | same |
| Screenshots | `app-store.md` §5 — do these after the device test |

Screenshots are required to *submit*, but not to save the listing or to file the
entitlement request. Leave them for later.

## 4. File the entitlement request

<https://developer.apple.com/contact/request/financekit>

Text is drafted in [`app-store.md`](./app-store.md) §0b. You'll need the app
record from step 2 to exist so you can point at it.

## 5. Privacy labels

**App Privacy** section. Guidance and the recommended answers are in
[`app-store.md`](./app-store.md) §3. Short version: the honest answer is "no
data collected", because data goes only to a destination the *user* operates —
but a conservative alternative answer is documented there too, and both survive
review.

---

## What I can automate once you're set up

Once the app record exists and you've done the Xcode Cloud grant, most ongoing
work is scriptable through the App Store Connect API — creating and editing
workflows, triggering builds, reading build status, and updating listing
metadata and localizations.

That needs an API key (Users and Access → Integrations → App Store Connect API,
**App Manager** role, download the `.p8`). Two caveats:

- I'd rather not handle the key material itself. Put the `.p8` somewhere
  gitignored and I'll reference it by path — I never need to read its contents.
- Submitting for review stays a manual step. That's publishing under your
  developer identity, and it should have a human pressing the button.
