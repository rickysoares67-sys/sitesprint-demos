# SpinRush upgrade package

**spinrush_chatgpt.html** is the whole site in one file: lobby, 40 games, engine, maths and betting.
It loads your original artwork from your site's `/static/assets/` folders, so no images are included here.

**To install on your ChatGPT site:** open ChatGPT, attach `spinrush_chatgpt.html`, and paste the text from `CHATGPT_PROMPT.md`.

## What's new
- Original maths for all 40 games, replacing the copied Book of Ra, Dolphin's Pearl, Fruit Shop and Sizzling Hot reels and paytables. Each game is tuned to about 84%, verified on 3 million spins (21 million for Hold & Spin games).
- 7 game styles, each playing its own way: Classic 5 Lines, Book Expansion, Triple Free Spins, Win-to-Spin, Hold & Spin, Sticky Wild Free Spins, Expanding Wild Respins.
- 7riches-style betting: choose lines, bet per line, total bet = lines × bet; MAX BET; red/black gamble after wins.
- New reel motion: acceleration, blur, bounce stops, teasing reels, win lines, big-win banners and sounds.

## Source (for future changes)
`source/` holds the engine (`engine.js`), app (`app.js`), page template (`ui.html`), the maths builder (`build.js`), the assembler (`make_site.py`), the tuned results (`games.json`) and the art map (`art_maps.json`).
