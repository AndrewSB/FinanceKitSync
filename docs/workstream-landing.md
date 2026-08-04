# Workstream C — Landing page

## Source

[`../landing/index.html`](../landing/index.html) — one self-contained file. No
build step, no dependencies, no external requests (the favicon is an inline SVG
data URI). Light and dark themes via `prefers-color-scheme`.

## Deploying to GitHub Pages

GitHub Pages publishes from a repository root, a `/docs` folder, or a
`gh-pages` branch — it can't publish an arbitrary subdirectory like `landing/`.
`/docs` is already the workstream documentation, so the page ships on a
`gh-pages` branch built from `landing/`:

```bash
./landing/publish.sh
```

Then, once only: **Settings → Pages → Source: Deploy from a branch →
`gh-pages` / `(root)`**.

Deliberately not a GitHub Actions workflow: the local `gh` token doesn't carry
the `workflow` scope, so pushing `.github/workflows/*` would be rejected. A
branch-based deploy needs no scope beyond `repo` and no extra moving parts.

> **Resolved 2026-08-04.** The repo is public and Pages is live. Two things had
> to happen: the free plan can't serve Pages from a private repo, and the
> account-level Pages custom domain `andrewsb.me` had stopped resolving — which
> made *every* project page 301 into a dead host. The domain was removed from
> `AndrewSB/andrewsb.github.io`, so the personal site is back on
> `andrewsb.github.io` and project pages resolve normally.

## Live URLs

| Page | URL | |
|---|---|---|
| Landing | <https://andrewsb.github.io/FinanceKitSync/> | 200 |
| Privacy | <https://andrewsb.github.io/FinanceKitSync/privacy.html> | 200 |
| Support | <https://andrewsb.github.io/FinanceKitSync/support.html> | 200 |

The privacy and support URLs are set on the App Store listing. Markdown mirrors
(`PRIVACY.md`, `SUPPORT.md`) stay in the repo root — they render on github.com
and are a working fallback if Pages ever breaks again.

If a custom domain is added later, put it in `landing/CNAME` and re-run
`landing/publish.sh`.

## Checklist

- [x] Repo public
- [x] `gh-pages` branch pushed
- [x] Pages source configured
- [x] Pages load over HTTPS
- [x] Custom-domain redirect problem resolved
- [ ] Renders correctly on a phone-width viewport
- [ ] Dark mode checked
- [ ] Landing page still says "FinanceKitSync" in places — the App Store name is
      now **FinanceKit Sync**, and the landing copy predates that decision
