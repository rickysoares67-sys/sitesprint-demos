"""Assemble index.html from ui.html + engine.js + app.js + game data.
python3 -I make_site.py CATALOGUE.json ART_MAPS.json GAMES.json"""
import json, sys
cat_path, art_path, games_path = sys.argv[1:4]
cat = json.load(open(cat_path))
art = json.load(open(art_path))
tuned = {g['id']: g for g in json.load(open(games_path))}
games = []
for g in cat:
    t = tuned[g['id']]
    games.append({
        'id': g['id'], 'name': g['name'], 'family': g['family'], 'volatility': g['volatility'],
        'accent': g.get('accent') or '#e5b84b', 'cover': g['cover'], 'names': (g.get('symbol_art') or {}).get('names', {}),
        'k': t['k'], 'rtp': t['rtp'], 'rtp1': t['rtp1'], 'hit': t['hit'], 'feat': t['feat'], 'big': t['big'], 'maxLines': t['maxLines'],
    })
map49 = {'s00': 0, 's01': 6, 's02': 1, 's03': 2, 's04': 5, 's05': 3, 's06': 7, 's07': 4, 's08': 11, 's09': 12, 's10': 13, 's18': 14, 's19': 15}
A51 = {k: dict(v, src=v['src'].lstrip('/')) for k, v in art['A51'].items()}
A52 = {k: dict(v, src=v['src'].lstrip('/')) for k, v in art['A52'].items()}
data = json.dumps({'games': games, 'A51': A51, 'A52': A52, 'map49': map49}, separators=(',', ':'), ensure_ascii=False)
ui = open('ui.html', encoding='utf-8').read()
for key, val in (('/*ENGINE*/', open('engine.js', encoding='utf-8').read()), ('/*DATA*/', data), ('/*APP*/', open('app.js', encoding='utf-8').read())):
    assert ui.count(key) == 1, key
    ui = ui.replace(key, val)
open('index.html', 'w', encoding='utf-8').write(ui)
# Standalone page for the ChatGPT-hosted site: full document, artwork from the site's own /static/assets/.
head = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '<style>[hidden]{display:none!important}:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}</style>\n'
        '<script>window.SPINRUSH_ASSET_BASE="/";</script>\n')
body_start = ui.index('<div class="wrap" id="lobby">')
full = head + ui[:body_start] + '</head>\n<body>\n' + ui[body_start:] + '\n</body>\n</html>\n'
full = full.replace('src="static/assets/art49/brand.svg"', 'src="/static/assets/art49/brand.svg"')
open('spinrush_chatgpt.html', 'w', encoding='utf-8').write(full)
print('spinrush_chatgpt.html', len(full), 'bytes')
print('index.html', len(ui), 'bytes;', len(games), 'games')

# Server build: the page runs in server mode; the server holds its own copy of the engine and the tuned game data.
import os, shutil
os.makedirs('server/public', exist_ok=True)
srv_head = head.replace('<script>window.SPINRUSH_ASSET_BASE="/";</script>', '<script>window.SPINRUSH_ASSET_BASE="/";window.SPINRUSH_SERVER=true;</script>')
open('server/public/index.html', 'w', encoding='utf-8').write(full.replace(head, srv_head))
json.dump([{'id': g['id'], 'family': g['family'], 'volatility': g['volatility'], 'name': g['name'], 'k': g['k']} for g in games],
          open('server/games_data.json', 'w'), separators=(',', ':'))
shutil.copyfile('engine.js', 'server/engine.js')
print('server build written (server/public/index.html, server/games_data.json, server/engine.js)')
