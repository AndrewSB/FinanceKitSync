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

> **Repository visibility.** The repo is currently **private**. GitHub Pages on
> a private repository requires a paid plan (Pro / Team / Enterprise). On the
> free plan, publishing requires making the repo public first — which is
> probably wanted anyway, since the App Store listing and the page itself both
> point at the source.

## URL

`https://andrewsb.github.io/FinanceKitSync/`

This goes in App Store Connect as both the marketing and support URL. If a
custom domain is added later, put it in `landing/CNAME` and re-run the publish
script.

## Checklist

- [ ] Repo made public (or Pages enabled on a paid plan)
- [ ] `gh-pages` branch pushed
- [ ] Pages source configured in repository settings
- [ ] Page loads over HTTPS
- [ ] Renders correctly on a phone-width viewport
- [ ] Dark mode checked
- [ ] Every link resolves (several point at files that must exist on `main`)
- [ ] Display name on the page matches the final App Store name
      (see [`app-store.md`](./app-store.md) — it may not stay "FinanceKitSync")
