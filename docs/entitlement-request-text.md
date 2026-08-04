# FinanceKit entitlement — explanation box

Draft text for the explanation field at
<https://developer.apple.com/contact/request/financekit>.

Two versions. **A** is the one to send, and requires the on-device financial
management surface described in [`app-store.md`](./app-store.md) §0 to exist
first. **B** describes the app as it stands today and is likely to be rejected.

---

## Version A — recommended (requires the Accounts + Trends screens)

> [App Name] is a personal finance app for iPhone, listed in the Finance
> category and distributed on the US App Store.
>
> It gives people a consolidated picture of their Apple Card, Apple Cash, and
> Apple Pay activity: current balances across all their accounts, a combined
> net position, and month-over-month spending trends grouped by merchant
> category. All of this is computed and displayed on device.
>
> The app additionally lets someone keep their own copy of that history on
> infrastructure they control. During setup they may enter an HTTPS endpoint
> they operate, and the app then mirrors their transactions there, so they can
> archive their financial history or analyze it with tools of their choosing.
> This is entirely optional; the app is fully functional without it.
>
> We operate no server and hold no user data. Transactions are read on device
> through FinanceKit only after the person grants permission, and are sent only
> to the address they themselves supply — over TLS, authenticated with a token
> they generate, and never to us. We have no technical means of accessing any
> user's financial data. The app contains no analytics, no advertising, and no
> third-party SDKs.
>
> On device we persist only an identifier and a checksum for each transaction
> already delivered, so the app knows what has changed since the last sync. No
> amounts, merchant names, or dates are stored outside FinanceKit itself.
>
> NSFinancialDataDescription is set in Info.plist, and access can be revoked at
> any time in Settings.
>
> We request the financial-data capability because reading the person's own
> transaction history is what makes both the on-device views and the optional
> export possible.

**Why this version works**

- Leads with the financial management tools the criteria ask for, as the
  product — not as an afterthought.
- Reframes self-hosting as *user control with safeguards* (TLS, user-generated
  token, opt-in, revocable) rather than *absence of oversight*.
- States the Finance category and US distribution explicitly, since both are
  criteria.
- Volunteers the privacy posture (no analytics, no SDKs, minimal on-device
  persistence) rather than waiting to be asked.
- First person plural and plain prose — matches how these requests are usually
  written and read.

---

## Version B — the app as it stands today

Use only if shipping without the management features is a deliberate decision.

> [App Name] is a data portability utility for iPhone, listed in the Finance
> category and distributed on the US App Store. It lets a person export their
> own Apple Card, Apple Cash, and Apple Pay transaction history to a server
> they operate.
>
> During setup the person enters an HTTPS endpoint belonging to them. The app
> reads their transaction history on device through FinanceKit, after they
> grant permission, and transmits it only to that address — over TLS,
> authenticated with a token they generate. There is no backend of ours in the
> path; we operate no server, hold no user data, and have no technical means of
> accessing anyone's financial information. The app contains no analytics,
> advertising, or third-party SDKs.
>
> The purpose is to let people keep and use their own financial records outside
> a single vendor's app — for personal archiving, budgeting in a tool of their
> choice, or analysis in a spreadsheet or database they own. Many people want
> their spending data in a form they control, and FinanceKit is the only
> supported way to obtain it on iOS.
>
> On device we persist only an identifier and a checksum for each transaction
> already delivered. No amounts, merchant names, or dates are stored outside
> FinanceKit.
>
> NSFinancialDataDescription is set in Info.plist, and access can be revoked at
> any time in Settings.

**Known weakness:** this does not claim the financial management tools the
published criteria require, because the app doesn't have them. Expect Apple to
cite that.

---

## Either way, don't include

- "Do whatever they want with the data" — accurate, but it reads as an absence
  of controls on financial data, which is the reviewer's core concern.
- "The app has no server" as an opening line. True and worth saying, but as
  reassurance partway through, not as the headline. Leading with an absence
  invites "then what does it do?"
- Any comparison to LunchSync unless asked. It's a different team and a
  different bundle ID, and volunteering it invites questions about why the
  existing approval doesn't cover this.

## Before submitting, confirm

- [ ] Signed in as **Account Holder**
- [ ] Account is **Organization**-level (see [`app-store.md`](./app-store.md) §0)
- [ ] App record exists with **Finance** primary category and **US** availability
- [ ] Final app name substituted for `[App Name]` throughout
- [ ] The claims in the text match what the app actually does at review time
