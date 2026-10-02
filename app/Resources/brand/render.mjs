// Renders the brand SVGs to the app icon (.icns) and menu-bar template PNGs. Run from repo root: node app/Resources/brand/render.mjs
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync, rmSync, readFileSync, copyFileSync } from 'node:fs';
const dir = 'app/Resources/brand', out = 'app/Resources';
const b = await chromium.launch();
async function shot(svgFile, px, pngOut) {
  const svg = readFileSync(`${dir}/${svgFile}`, 'utf8');
  const p = await b.newPage({ viewport: { width: px, height: px }, deviceScaleFactor: 1 });
  await p.setContent(`<html><body style="margin:0;background:transparent">${svg.replace(/<svg /, `<svg style="width:${px}px;height:${px}px;display:block" `)}</body></html>`);
  await p.screenshot({ path: pngOut, omitBackground: true, clip: { x: 0, y: 0, width: px, height: px } });
  await p.close();
}
rmSync(`${dir}/AppIcon.iconset`, { recursive: true, force: true }); mkdirSync(`${dir}/AppIcon.iconset`);
await shot('app-icon.svg', 1024, `${dir}/icon-1024.png`);
for (const [name, px] of [['icon_16x16', 16], ['icon_16x16@2x', 32], ['icon_32x32', 32], ['icon_32x32@2x', 64], ['icon_128x128', 128], ['icon_128x128@2x', 256], ['icon_256x256', 256], ['icon_256x256@2x', 512], ['icon_512x512', 512], ['icon_512x512@2x', 1024]]) {
  execSync(`sips -z ${px} ${px} "${dir}/icon-1024.png" --out "${dir}/AppIcon.iconset/${name}.png" >/dev/null`);
}
execSync(`iconutil -c icns "${dir}/AppIcon.iconset" -o "${out}/AppIcon.icns"`);
await shot('menubar-template.svg', 18, `${dir}/menubar-18.png`);
await shot('menubar-template.svg', 36, `${dir}/menubar-36.png`);
await shot('mark-mint.svg', 256, `${dir}/mark-mint-256.png`);
await b.close();
console.log('wrote AppIcon.icns, menubar-18/36.png, mark-mint-256.png');
