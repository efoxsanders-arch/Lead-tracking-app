# Lead Tracker
Working title. Tracks purchased leads so the money spent on them isn't wasted. Sister app to the Invoice App and built the same way.

## What it does (step 1)
- **Today:** leads waiting for a first contact (longest wait first, flagged late after 15 minutes), follow-ups due, and leads going cold
- **Leads:** add a lead with its source and cost; log every call, text, email or visit; the next follow-up date is suggested (1, 2, 3, 5, then 7 days)
- **Outcome:** new, contacted, quoted, won (with amount) or lost (with reason)
- **Bad leads:** mark wrong numbers, duplicates and out-of-area leads, and track whether the vendor credited you
- **Costs:** spend, revenue and return per lead source, time to first contact, and where lead money is leaking
- **Setup:** lead sources with a usual cost per lead, and alert timings

## Accounts and automatic intake (step 2)
Signed out, leads are saved in the browser on that device. Signed in, they are saved to the account and new leads arrive on their own. The app uses the same Supabase project and the same accounts as the Invoice App.

**Turn it on (one time)**
1. In Supabase → **SQL Editor**, run `supabase/setup.sql`. It's safe to re-run.
2. In Supabase → **Edge Functions**, create a function named `lead-intake`, paste in `supabase/functions/lead-intake/index.ts`, turn **Verify JWT off**, and deploy. Lead vendors can't sign in, so the function checks each account's private key instead.
3. In **Authentication → URL Configuration**, add this app's web address to **Redirect URLs** so sign-up and password-reset emails lead back here.
4. Put the app online (GitHub Pages, like the Invoice App). Sign-in is switched off inside previews and embedded frames.

**Connect lead vendors:** sign in, open **Setup → Automatic lead intake**, and copy each address into the vendor.
- **Google Ads lead forms:** paste the webhook URL and key into the lead form, then press "Send test data".
- **Angi / HomeAdvisor:** email the address to Angi's CRM integrations team. Angi sends the real fee with each lead, and the app uses it as the lead's cost.
- **Thumbtack:** add a Leads webhook in the Thumbtack pro account.
- **Anything else:** send JSON with `name`, `phone`, `email`, `service`, `notes`, `cost`.

While the app is open, a new lead appears within seconds with a sound and, if allowed, a notification. Alerts while the app is closed (text or email to the rep) are not built yet.

## Next steps
- Alerts by text or email when the app is closed
- Google Local Services through the Google Ads API (needs Google's approval for API access)
- Instant first reply to new leads, and a team and manager view

## Project layout
- `src/app.html` – the app's source (styles, markup and script in one file)
- `build.sh` – wraps the source into `index.html`
- `index.html` – the built app; open it in any browser
- `supabase/setup.sql` – database tables, security rules and the intake routine
- `supabase/functions/lead-intake/index.ts` – receives leads from vendors

After editing `src/app.html`, run `./build.sh`.
