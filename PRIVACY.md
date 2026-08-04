# Privacy Policy for FinanceKit Sync

**Effective date:** August 4, 2026
**Last updated:** August 4, 2026

App: **FinanceKit Sync** (bundle ID `com.asb.FinanceKitSync`)
Developer: **Andrew Breckenridge**, an individual developer based in the United States
Contact: **asbreckenridge@me.com**

## Overview

FinanceKit Sync reads your Apple Card, Apple Cash, and Apple Pay transaction history from your iPhone and sends it to a server that you choose and operate.

There is no service behind this app. The developer does not run a server, does not host an account system, and does not receive your data. You enter the address of your own server, and the app sends your transactions there and nowhere else.

There is no account, no login, and no hosted backend.

## What data the app accesses

With your permission, the app uses Apple's FinanceKit framework to read transaction history for:

- Apple Card
- Apple Cash
- Apple Pay

This includes the transaction details FinanceKit provides, such as amounts, merchant descriptions, dates, and transaction identifiers.

iOS will not give the app any of this data until you explicitly grant FinanceKit permission. You can revoke that permission at any time in **Settings → Privacy & Security** on your device. If you revoke it, the app can no longer read your transactions.

The app does not access your contacts, photos, location, microphone, camera, health data, or any other category of personal data.

## What is transmitted, and where

Transaction data is sent **only** to the server URL you enter in the app. You choose that destination. You control it. The app has no other destination built in, and no default or fallback server.

- Transmission is **HTTPS only**. The app refuses to accept or use a URL that is not HTTPS.
- Each request is authenticated with a bearer token that **you** supply and that your server checks.
- Nothing is sent to the developer, and nothing is routed through any intermediary service.

If you never configure a server URL, the app has nowhere to send data and sends nothing.

## What is stored on your device

The app stores the following locally on your iPhone, and nowhere else:

1. **The bearer token** you supply, stored in the iOS Keychain.
2. **The server URL** you enter, stored in the app's preferences.
3. **Sync status** — whether background sync is enabled, when the last sync ran, and the last error message, if any.
4. **A local ledger** of what has already been delivered. For each already-delivered transaction, the ledger holds only:
   - an identifier,
   - a SHA-256 checksum, and
   - a timestamp.

   The ledger exists so the app knows what it has already sent and does not send it twice.
5. **An activity log** for troubleshooting — a bounded, rolling record of sync events: timestamps, counts of accounts and transactions processed, and any error messages. Where an error concerns a specific account, the log may include that account's display name (for example, "Apple Card"). You can view, export, and clear this log in the app under **Activity log**.

**The app does not persist transaction amounts, merchant names, or transaction dates.** Those values are read, transmitted to your server, and not written to the app's own storage.

All of the above stays on your device. None of it is transmitted anywhere, including to the developer.

## What the developer collects

**Nothing.**

The developer receives no user data whatsoever and has no technical means of accessing it. There is no developer-operated server, database, log, or endpoint that your data could reach. Your transaction data goes from your iPhone to your server, and the developer is not part of that path.

## Third parties

The app contains:

- **No analytics.**
- **No advertising.**
- **No tracking or tracking identifiers.**
- **No crash reporting.**
- **No third-party SDKs of any kind.**

No data is sold, shared, rented, or disclosed to anyone. There is nothing to sell — the developer never has your data.

The only network connection the app makes is to the server URL you configure.

## Your choices and control

- **Grant or revoke access.** FinanceKit access is entirely under your control in iOS Settings → Privacy & Security. Revoking it stops the app from reading transactions.
- **Choose the destination.** You decide what server receives your data, and you can change or clear the server URL at any time.
- **Control the credentials.** The bearer token is yours. You can change it, and you can invalidate it on your server.
- **Stop entirely.** Delete the app and it stops reading and sending anything.

## Data retention and deletion

- **On your device:** deleting FinanceKit Sync removes all data the app stored locally, including the server URL, sync status, the local ledger, the activity log, and the bearer token held in the Keychain.
- **On your server:** any data already sent to your server is under your control. Retention and deletion there are governed by how you have configured your own system. The developer cannot access, retrieve, or delete it.
- **With the developer:** there is nothing to delete, because the developer holds nothing.

## Security

- Transactions are transmitted over HTTPS. The app rejects non-HTTPS URLs.
- Requests are authenticated with a bearer token you supply.
- The bearer token is stored in the iOS Keychain, which is protected by the device's hardware-backed encryption and passcode.
- Transaction data is read from FinanceKit and sent; amounts, merchant names, and dates are not written to persistent app storage.

**Because you operate the destination server, securing it is your responsibility.** That includes keeping its TLS configuration current, protecting the bearer token, restricting who can reach the server, and securing whatever storage or backups your server keeps. The developer has no control over and no visibility into your server.

## Children's privacy

FinanceKit Sync is not directed to children under 13, and the developer does not knowingly collect any information from children. The app depends on Apple Card, Apple Cash, and Apple Pay accounts, which are not available to children under 13.

## GDPR and CCPA note

Because the developer never receives your transaction data, the developer is **not a data controller or a data processor** for that data. You determine what is collected, where it goes, and how long it is kept — those decisions are yours, made on infrastructure you operate.

If you are in the European Economic Area, the United Kingdom, or California, you still hold your rights under applicable law, including rights of access, correction, deletion, and portability. Those rights are exercised against whoever actually holds your data. In this case, that is you and your own server.

The developer does not sell or share personal information, and there is no personal information held by the developer to access, correct, delete, or port. If you have a question or want to raise a privacy request anyway, you are welcome to contact the developer at the address below.

## Changes to this policy

If this policy changes, the updated version will be posted with a new "Last updated" date. Material changes will be reflected in the app's App Store listing. Because the developer holds no user data and has no account system, there is no way to notify you directly, so please check this page if you want to stay current.

## Contact

Andrew Breckenridge
Email: **asbreckenridge@me.com**
