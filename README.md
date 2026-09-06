# FinanceKitSync

An iPhone app that mirrors your Apple Card, Apple Cash, and Apple Pay
transactions to a server **you** control. No account, no hosted backend, no
third party in the path.

Split out of [LunchSync](https://github.com/AndrewSB/LunchSync), which syncs the
same FinanceKit data into Lunch Money specifically. This project keeps only the
generic half: read everything FinanceKit has, ship it to an endpoint you choose,
and get out of the way.

## Repository layout

```
app/       the iOS app (Xcode 27, iOS 18+, SwiftUI)
server/    the receiving server (FastAPI + SQLite, Docker)
landing/   the GitHub Pages landing page
docs/      spec, workstream tracking, App Store material
```

## Start here

- **[docs/SPEC.md](docs/SPEC.md)** — what this is, how it works, the threat model
- **[docs/STATUS.md](docs/STATUS.md)** — where every workstream stands
- **[docs/releasing.md](docs/releasing.md)** — how a build reaches the App Store
- **[server/README.md](server/README.md)** — running the server

## Status

🟠 **Working; rejected once by App Review, fix built.** The
`com.apple.developer.financekit` entitlement was approved and provisioned on
2026-08-06, the app builds and passes 52 tests, the server is deployed and
verified, and the app was confirmed working on a real iPhone on 2026-08-07.
Version 1.0 was rejected on 2026-09-06 under guideline 2.1 because reviewers
had no way to use it without a server. The app now has a **demo mode** ("Try
the demo" on the Connect screen) that runs the whole pipeline against sample
transactions and a built-in stand-in server. Resubmission is the next step.

**[docs/STATUS.md](docs/STATUS.md) is the single source of truth**, and opens
with exactly where things stand and what is still owed.

## License

MIT
