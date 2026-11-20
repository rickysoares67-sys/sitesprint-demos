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
print('index.html', len(ui), 'bytes;', len(games), 'games')
