/* usage: node render-world.cjs <world> <out-dir> — renders scenes (every scene+state used by the data), characters and
   relics of one world to PNGs. Needs /tmp/render-<world>.js (bundled render-entry.ts) and data/worlds/<world>.json. */
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/npm-tools/node_modules/playwright');
const [world, out] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../data/worlds', world + '.json'), 'utf8'));
const combos = new Map(); data.scenes.forEach(s => combos.set(s + '|{}', [s, {}]));
const walk = v => { if (Array.isArray(v)) return v.forEach(walk); if (v && typeof v === 'object') { if (typeof v.scene === 'string' && v.state && Object.keys(v.state).length) combos.set(v.scene + '|' + JSON.stringify(v.state), [v.scene, v.state]); Object.values(v).forEach(walk); } };
walk(data.weeks);
const key = (s, st) => Object.keys(st).length ? s + '__' + Object.entries(st).sort().map(([k, v]) => k + '-' + v).join('_') : s;
const save = (f, url) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, Buffer.from(url.split(',')[1], 'base64')); };
(async () => {
  const br = await chromium.launch(); const pg = await br.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  await pg.setContent('<html><body></body></html>'); await pg.addScriptTag({ path: '/tmp/render-' + world + '.js' });
  const list = [...combos.values()];
  const urls = await pg.evaluate(l => window.scenes(l), list);
  list.forEach(([s, st], i) => save(path.join(out, 'bg', world, key(s, st) + '.png'), urls[i]));
  const ids = [...new Set([...Object.keys(data.cast), 'you', 'narrator'].filter(x => x !== 'narrator'))];
  const cu = await pg.evaluate(l => window.chars(l), ids);
  ids.forEach((id, i) => save(path.join(out, 'chars', id + '.png'), cu[i]));
  for (const [id, u] of await pg.evaluate(() => window.relics())) if (u) save(path.join(out, 'relics', id + '.png'), u);
  console.log(list.length + ' scenes, ' + ids.length + ' chars', errs.slice(0, 3).join(' | '));
  await br.close();
})();
