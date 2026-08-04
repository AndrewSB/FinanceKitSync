# tools

## App Store Connect

Credentials come from the environment and are never stored in the repo:

```bash
export ASC_KEY_ID=K7ADUCTS7A
export ASC_ISSUER_ID=69a6de8c-48a9-47e3-e053-5b8c7c11a4d1
export ASC_KEY_PATH=~/Downloads/AuthKey_K7ADUCTS7A.p8   # move somewhere permanent
```

> Move the `.p8` out of `~/Downloads` — Apple lets you download it exactly once,
> and losing it means revoking the key and issuing a new one. `*.p8` is
> gitignored, so it can't be committed by accident.

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
