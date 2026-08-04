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

Pre-release. The app builds and the server is deployed and tested, but
distribution is blocked on Apple approving the `com.apple.developer.financekit`
entitlement — see [docs/app-store.md](docs/app-store.md).

## License

MIT
