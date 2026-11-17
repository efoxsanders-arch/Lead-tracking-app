# Lead Tracker
Working title. Tracks purchased leads so the money spent on them isn't wasted. Sister app to the Invoice App and built the same way.

## What it does (step 1)
- **Today:** leads waiting for a first contact (longest wait first, flagged late after 15 minutes), follow-ups due, and leads going cold
- **Leads:** add a lead with its source and cost; log every call, text, email or visit; the next follow-up date is suggested (1, 2, 3, 5, then 7 days)
- **Outcome:** new, contacted, quoted, won (with amount) or lost (with reason)
- **Bad leads:** mark wrong numbers, duplicates and out-of-area leads, and track whether the vendor credited you
- **Costs:** spend, revenue and return per lead source, time to first contact, and where lead money is leaking
- **Setup:** lead sources with a usual cost per lead, and alert timings

Leads are saved in the browser on each device for now.

## Next steps
2. Accounts (shared with the Invoice App) and automatic intake: each customer gets a private web address to paste into Google Ads lead forms, Angi/HomeAdvisor and Thumbtack. `supabase/setup.sql` holds the tables for this.
3. Google Local Services through the Google Ads API, instant first reply to new leads, team and manager view.

## Project layout
- `src/app.html` – the app's source (styles, markup and script in one file)
- `build.sh` – wraps the source into `index.html`
- `index.html` – the built app; open it in any browser
- `supabase/setup.sql` – database tables for step 2

After editing `src/app.html`, run `./build.sh`.
