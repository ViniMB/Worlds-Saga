/* Bundled for the browser (esbuild) and driven by render-world.cjs (Playwright): draws a My English world's pixel art
   onto canvases and returns PNG data URLs — animated scene sheets, character sheets and relic icons. */
import W from 'WORLD';
import { CAST as BASE } from '/home/claude/my-english/src/worlds/season/cast';
import { person } from '/home/claude/my-english/src/worlds/season/art';
import { shapeUrl } from '/home/claude/my-english/src/worlds/season/sprites';

const FR = 8, STEP = 160;
const cv = (w: number, h: number) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
(window as any).scenes = (combos: [string, Record<string, unknown>][]) => combos.map(([id, st]) => {
  const c = cv(144 * FR, 96), x = c.getContext('2d')!;
  for (let i = 0; i < FR; i++) { x.save(); x.beginPath(); x.rect(i * 144, 0, 144, 96); x.clip(); x.translate(i * 144, 0); try { (W as any).scenes[id](x, 1000 + i * STEP, st || {}); } catch (e) { x.fillStyle = '#f0f'; x.fillRect(0, 0, 144, 96); } x.restore(); }
  return c.toDataURL();
});
/* a character sheet: 32×32 cells — idle, blink, talk A, talk B, idle t+, flip idle */
(window as any).chars = (ids: string[]) => ids.map(id => {
  const all: any = { ...BASE, ...(W as any).cast };
  let p = all[id]; if (id === 'you') p = { ...BASE.you, look: (W as any).you ? (W as any).you({ relics: [], flags: [], done: {}, paths: [] }) : BASE.you.look };
  const c = cv(32 * 6, 32), x = c.getContext('2d')!;
  const opts = [{ t: 0 }, { t: 0, blink: true }, { t: 0, talk: true }, { t: 260, talk: false }, { t: 600 }, { t: 0, flip: true }];
  opts.forEach((o, i) => { x.save(); x.translate(i * 32, 0); try { if (p?.draw) p.draw(x, 9, 4, o); else if (p?.look) person(x, p.look, 9, 4, o as any); } catch (e) { /* skip */ } x.restore(); });
  return c.toDataURL();
});
(window as any).relics = () => ((W as any).relics || []).map((r: any) => [r.id, shapeUrl(r.art, r.tint, r.accent)]);
(window as any).ids = () => Object.keys((W as any).scenes);
