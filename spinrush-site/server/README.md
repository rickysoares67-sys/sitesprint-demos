# SpinRush game server

Every spin, bonus feature and gamble is decided **on this server**, never in the player's browser.
The browser only sends "spin this game, this many lines, this bet per line" and animates the result it gets back.
Virtual play-money only: there are no deposit, payment or withdrawal endpoints.

## What it does
- **Secure randomness:** every outcome uses Node's cryptographically secure generator (`crypto.randomInt`).
- **Server-held balances:** the balance lives on the server. Changing numbers in the browser does nothing.
- **Strict checks:** only real games, 1 to max lines, offered bets, enough balance, one round at a time, no spamming.
- **Audit trail:** every spin, gamble, collect and top-up is appended to `data/rounds.jsonl` with time, game, bet, reel stops, win and balance before and after. Players are recorded by a one-way hash, never their session key.
- **Sessions:** a random 256-bit ID in an HttpOnly cookie (Secure when served over HTTPS).

## Run it
Needs Node.js 18 or newer. No other packages.

```
cd server
cp -r ../static ./static      # your artwork (or set STATIC_DIR to wherever /static lives)
node server.js                # http://localhost:8080
```

Settings (environment variables): `PORT` (default 8080), `DATA_DIR` (default `./data`), `STATIC_DIR` (default `./static`).

## Put it online
Any host that runs Node works (Render, Railway, Fly.io, a VPS). Use the start command `node server.js` and give it a persistent disk for `DATA_DIR`. Serve it over **HTTPS**.

## API
| Call | Purpose |
|---|---|
| `GET /api/session` | Current balance (creates a play-money account on first visit) |
| `POST /api/spin` `{game, lines, lineBet}` | Settles a full round (base spin + any bonus), returns the steps to animate and the new balance |
| `POST /api/gamble` `{pick: "red" \| "black" \| "collect"}` | Double-or-nothing on the last win (fair 50/50, up to 5 times, wins up to R 2 500) |
| `POST /api/topup` | Resets the play-money balance to R 25 000 when it is below that |

## Tests
`node test_api.js` checks validation and cheating attempts, exact money movement, the gamble's fairness, the audit log, and the payout rate of 1.2 million server-settled spins.

## Before real money (not built, and not legal without a licence)
This server fixes the "outcomes in the browser" problem. A licensed real-money casino would still need:
- independent lab certification of the RNG and every game's maths
- a real database with backups instead of the JSON file
- player identity checks, anti-money-laundering controls and responsible-gambling limits
- payment processing approved for gambling
- a gambling licence, which in South Africa means getting legal advice first
