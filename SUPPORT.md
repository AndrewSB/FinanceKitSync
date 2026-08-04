# FinanceKit Sync — Support

Setup help, troubleshooting, and how to get in touch.

## Getting in touch

Email [asbreckenridge@me.com](mailto:asbreckenridge@me.com), or open an
issue at [github.com/AndrewSB/FinanceKitSync/issues](https://github.com/AndrewSB/FinanceKitSync/issues).

If something went wrong during a sync, go to **Activity log** in the
app, tap **Export**, and include the output. It contains no amounts or
merchant names.

## Setting up a server

This app has no hosted backend — you point it at a server you run. The receiver is
a small open-source Python service; it runs anywhere Docker does, including a VPS,
a home server, or a Raspberry Pi.

```bash
git clone https://github.com/AndrewSB/FinanceKitSync
cd FinanceKitSync/server

printf 'FKS_TOKEN=%s\n' "$(openssl rand -hex 20)" > .env
mkdir -p data && chown -R 10001:10001 data
docker compose up -d --build

curl http://127.0.0.1:8501/health
# {"status":"ok","schema_version":1}
```

The app requires `https://`, so put it behind a reverse proxy with a real
certificate. If you would rather not open a port or manage DNS, Tailscale Funnel
does both in one command:

```bash
tailscale funnel --bg --https=8443 http://127.0.0.1:8501
```

Then enter that URL and the token you generated under *Connect your server*
in the app, and tap *Test connection*.

## Troubleshooting

### "Couldn't reach the server"

The address isn't resolving or nothing is listening. Check the server is running
(`docker compose ps`), that the URL includes the right port, and — if
you're using Tailscale without Funnel — that your iPhone is connected to the same
tailnet.

### "The server refused the token"

The address is right but the token doesn't match. Compare it against
`FKS_TOKEN` in your server's `.env` file. Tokens are
case-sensitive and easy to truncate when copying.

### "Something is listening, but it isn't a FinanceKit Sync server"

Something answered, but not our server — usually a reverse proxy pointing at the
wrong service, or a captive portal. Check that `/health` returns
`{"status":"ok"}`.

### "Financial data isn't available on this device"

iOS isn't providing access. Check **Settings → Privacy & Security →
Financial Data** and confirm the app is allowed. Note that financial data
is only available on iPhone, and only in supported regions.

### Syncs aren't happening on their own

iOS decides when background refresh runs — it isn't a fixed schedule, and it can
be delayed when the device is on battery or rarely used. Open the app and pull
down to refresh whenever you want an immediate sync.

### I rebuilt my server and it's empty

Go to **Settings → Re-send everything**. That clears the app's record
of what has already been delivered, so the next sync replays your full history.
Nothing is deleted from your device, and duplicates aren't created — the server
keys on each transaction's identifier.

## Privacy

Your transactions are read on your iPhone and sent only to the address you enter.
Nothing is sent to us — there is no server on our side to receive it. See the
[privacy policy](PRIVACY.md).
