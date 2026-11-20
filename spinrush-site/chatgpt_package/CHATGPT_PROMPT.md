I'm upgrading my SpinRush site. The attached file **spinrush_chatgpt.html** is a complete, self-contained replacement for my lobby and game pages. It contains a new game engine, original game maths, and new betting and gameplay. Please install it exactly as provided.

## What to do
1. Replace my homepage (`/`) with `spinrush_chatgpt.html`, unchanged. Serve it as the site's index page.
2. Make `/vip` and `/vip.html` show the same page (or redirect to `/`). Games now open inside this page with links like `/#play-temple`.
3. Keep every image file in `/static/assets/` exactly where it is. The new page loads my original artwork from these folders: `art49/`, `art51/`, `art52/`, `art55/` and `posters35/`. Do not delete, rename, move, compress or regenerate any of them.
4. `catalogue.json` and the old engine are no longer used by the new page. You can leave them in place.

## Do not change
- The code inside the `<script>` that defines **SREngine**. That is the game maths.
- The **SITE** data object. Its `k` values tune each game to its tested payout rate (about 84%). Changing any number breaks the tested maths.
- The betting logic (lines, bet per line, total bet, gamble) and the 25 payline definitions.
- Do not "optimise", minify, reformat or split the file. Keep it as one file.

## Keep these rules
- Virtual play-money only: no deposits, no cash prizes, no withdrawals, no real-money purchases of credits.
- Keep the 18+ age check and the "virtual play-money only · no cash value" notices.

## After installing, check
- The homepage shows the SpinRush logo, the "Virtual balance · ZAR" box and **40 games** with their posters.
- Open **Temple of Titans**. You should see LINES and BET / LINE buttons, the reels should spin and stop one by one, and RULES should show a payout rate of about 84%.
- Images load (no broken images) and the browser console shows no errors.

If anything doesn't load, tell me which file or path fails. Don't rewrite the game code to work around it.
