// Bundled with esbuild and run in node: dumps a My English world (weeks, steps, cast looks, relics) to JSON.
import W0 from 'WORLD';
(async () => {
  const W: any = W0;
  const strip = (v: any): any => typeof v === 'function' ? undefined : Array.isArray(v) ? v.map(strip) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).filter(([k]) => k !== 'draw').map(([k, x]) => [k, strip(x)])) : v;
  const cast = Object.fromEntries(Object.entries(W.cast || {}).map(([k, p]: any) => [k, { id: p.id, name: p.name, role: p.role, color: p.color, custom: !!p.draw }]));
  const out = { id: W.id, title: W.title, tagline: W.tagline, color: W.color, intro: W.intro, roads: W.roads, relics: W.relics, ranks: W.ranks, home: W.home, targets: W.targets, cast, weeks: strip(W.weeks), scenes: Object.keys(W.scenes || {}) };
  console.log(JSON.stringify(out, null, 1));
})();
