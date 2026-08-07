# App Store listing — paste-ready

Everything to fill in the App Store Connect record. Copy as-is.

---

## The name — decided, with the risk accepted

The App Store display name is **"FinanceKit Sync"**, and 1.0 is in review under
it.

This section previously said the name *must* change. The reasoning: Apple's
[trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
say you may not use an Apple trademark, in whole or in part, in a product name,
and `FinanceKit` is an Apple framework name. Alternatives were drafted —
*Ledgerline*, *Cardpost*, *Ownledger*, *Tallyport*, *Passage*.

The decision on 2026-08-04 was to keep "FinanceKit Sync" anyway: "FinanceKit" is
absent from Apple's published trademark list while every sibling framework is
registered, and the downside is a metadata rejection that is fixable the same
day without a new binary. That bet has not yet been settled — the app is in
review, not approved.

**If Apple objects, the fix is small:** change the name in `tools/listing.json`
and re-apply with `tools/push_listing.py`. The bundle ID, repo, and binary are
unaffected.

---

> **`tools/listing.json` is the source of truth for the listing**, not this
> file. It is what gets pushed to App Store Connect and what has actually been
> applied. Treat the values below as the human-readable rationale.

## App Information

| Field | Value |
|---|---|
| Name | `FinanceKit Sync` |
| Subtitle | `Your transactions, your server` *(29 chars)* |
| Primary category | **Finance** ← required by the FinanceKit criteria |
| Secondary category | Utilities |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ |

## Pricing and Availability

| Field | Value |
|---|---|
| Price | Free |
| Availability | **United States** at minimum — FinanceKit is US/UK only |

## Description

```
Your Apple Card, Apple Cash, and Apple Pay transactions belong to you.
FinanceKit Sync puts them somewhere you can actually use them.

Point it at a server you run, and it copies your transaction history there —
your full history, not just the last month — and keeps it current as new
charges post. What you build on top of that is up to you: a database, a
spreadsheet, a budgeting tool, a dashboard, a personal archive.

HOW IT WORKS
• Your transactions are read on your iPhone.
• They're sent over an encrypted connection to the address you enter.
• Nothing goes anywhere else. There is no account and no service in between.

WHAT'S SENT
Every field available: amount, currency, date, posted date, merchant name and
category code, transaction type, pending or posted status, and foreign currency
amounts and exchange rates where applicable.

WHAT'S STORED ON YOUR PHONE
Only a record of what has already been delivered — an identifier and a checksum
per transaction. No amounts. No merchant names.

YOU NEED YOUR OWN SERVER
FinanceKit Sync does not come with one, and there is no hosted option. The setup
guide covers running the open-source receiver on any machine you control. If
you would rather not run a server, this app is not for you.

Open source: github.com/AndrewSB/FinanceKitSync
```

> Note the description says "read on your iPhone" rather than naming the
> framework. Referential use of "Apple Card" / "Apple Cash" / "Apple Pay" is
> fine — those are the products the data comes from, which is exactly the
> permitted compatibility reference.

## Keywords (100 characters)

```
apple card,export,transactions,self-hosted,finance,sync,backup,privacy,budget,api,csv,wallet
```

## Required URLs

| Field | Value |
|---|---|
| Support URL | **needed — see below** |
| Marketing URL | optional; may be left blank |
| Privacy Policy URL | **required to submit — see below** |

### ⚠️ You need two URLs and don't currently have either

The landing page was dropped from scope, but **App Store Connect will not let
you submit without a Privacy Policy URL**, and a Support URL is also required.

Cheapest options that don't resurrect the landing page:

1. **A markdown file in the repo** — requires making the repo public, then
   linking `https://github.com/AndrewSB/FinanceKitSync/blob/main/PRIVACY.md`.
   Free, no hosting, but the repo must be public.
2. **A GitHub Gist** — works with a private repo, takes two minutes, and gives a
   stable URL.
3. **Serve them from `box`** — the server is already running behind Tailscale;
   adding two static routes and exposing them via Funnel would work, but ties
   your App Store listing's availability to your home server. Not recommended.

Option 1 is cleanest if the repo is going public anyway. Say which and I'll
write the privacy policy and support page.

## App Review notes

See [`app-store.md`](./app-store.md) §4 — includes the test-server placeholder
and the "zero transactions is correct behaviour" note.

## Privacy labels

See [`app-store.md`](./app-store.md) §3.

---

## What I can automate

App-record *creation* isn't in the App Store Connect API, so that part was
manual. But everything on this page **is** API-writable — name, subtitle,
description, keywords, URLs, and localizations, via
`appStoreVersionLocalizations` and `appInfoLocalizations`.

Give me a path to an App Store Connect API key (`.p8`, App Manager role) and
I'll push this whole listing in one shot, so it lives in version control rather
than being retyped into a web form.
