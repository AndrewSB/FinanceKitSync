# tools

## App Store Connect

Credentials come from the environment and are never stored in the repo:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

> Apple lets you download the `.p8` exactly once — losing it means revoking the
> key and issuing a new one. `*.p8` is gitignored so it can't be committed by
> accident, and the key/issuer IDs are deliberately not recorded here since this
> repository is public.

| File | |
|---|---|
| `asc.py` | Minimal API client. Signs its own ES256 JWT with `cryptography`, because PyJWT has no wheel for the Python 3.14 on this machine. |
| `listing.json` | The App Store listing, as data. Edit this, not the web form. |
| `push_listing.py` | Pushes `listing.json`. Idempotent; dry-run by default. |
| `subscription.json` | The v1.1 auto-renewable subscription, as data. |
| `push_subscription.py` | Pushes `subscription.json` — group, product, price, localization, free trial, availability, review screenshot. Idempotent; dry-run by default. **Never yet run against the live account.** |
| `screenshots.sh` | Captures the six listing screens at both required sizes, from synthetic data. The last, `paywall`, is also the subscription's review screenshot. |
| `push_screenshots.py` | Uploads what `screenshots.sh` produced. Idempotent; dry-run by default. |
| `ExportOptions.plist` | Re-signs the archive for the App Store. A plain `archive` is signed for development and App Store Connect rejects it. |

```bash
python3 tools/asc.py whoami              # verify credentials
python3 tools/push_listing.py            # show what would change
python3 tools/push_listing.py --apply    # write it

./tools/screenshots.sh                   # capture
python3 tools/push_screenshots.py --apply

python3 tools/push_subscription.py       # v1.1 — show what would change
python3 tools/push_subscription.py --apply
```

> In-app purchase endpoints all 403 until the **Paid Applications agreement** is
> signed in App Store Connect. That is a web-UI step and comes first.

### Shipping a build

```bash
cd app && xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates -archivePath ../build/FinanceKitSync.xcarchive archive

env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive \
  -archivePath build/FinanceKitSync.xcarchive -exportPath build/export \
  -exportOptionsPlist tools/ExportOptions.plist -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"

xcrun altool --upload-app -f build/export/FinanceKitSync.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

> The scrubbed `PATH` on the export is load-bearing, not superstition. Homebrew's
> rsync 3.4.4 shadows `/usr/bin/rsync`, and Xcode's IPA packaging step calls
> `rsync -E`, which it rejects. The failure surfaces as an unexplained
> "Copy failed".
>
> `altool` finds the key by ID, searching `./private_keys`, `~/private_keys`,
> `~/.private_keys`, and `~/.appstoreconnect/private_keys` — it ignores
> `ASC_KEY_PATH`, so the `.p8` has to actually be in one of those.

### The app record must be created by hand, once

The API refuses to create apps:

```
The resource 'apps' does not allow 'CREATE'.
Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE
```

So that first step is the web UI. Everything after it — name, subtitle,
categories, description, keywords, promotional text, URLs, version records — is
handled by `push_listing.py`.
