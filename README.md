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
- **[server/README.md](server/README.md)** — running the server

## Status

⏸️ **Parked, waiting on Apple.** The app builds and passes 44 tests, the server
is deployed and verified, and the App Store listing is complete — but the
`com.apple.developer.financekit` entitlement (request `453VPT726K`) is pending,
and without it the app **cannot be signed for a device at all**. So no build
exists, and no real transaction has ever been read.

**[docs/STATUS.md](docs/STATUS.md) is the single source of truth**, and starts
with a step-by-step *"Resume here when the entitlement is approved"* runbook.

## License

MIT
