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

```bash
python3 tools/asc.py whoami            # verify credentials
python3 tools/push_listing.py          # show what would change
python3 tools/push_listing.py --apply  # write it
```

### The app record must be created by hand, once

The API refuses to create apps:

```
The resource 'apps' does not allow 'CREATE'.
Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE
```

So that first step is the web UI. Everything after it — name, subtitle,
categories, description, keywords, promotional text, URLs, version records — is
handled by `push_listing.py`.
