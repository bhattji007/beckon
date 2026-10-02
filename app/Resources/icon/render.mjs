#!/usr/bin/env node
// Renders the Beckon app icon and menu-bar glyph.
//
//   node app/Resources/icon/render.mjs        (run from the repo root, needs node_modules/playwright)
//
// Outputs (all under app/Resources):
//   icon/icon-1024.png              master render of icon.html
//   icon/AppIcon.iconset/*.png      16…512 incl. @2x, Apple naming
//   AppIcon.icns                    built with iconutil (picked up by app/build.sh)
//   icon/menubar-22.png, -44.png    white-on-transparent bell for the NSStatusItem
//   icon/preview-32.png             32 px check render (for eyeballing legibility)

import { chromium } from 'playwright';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync, rmSync, existsSync, copyFileSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));          // app/Resources/icon
const resources = dirname(here);                                 // app/Resources
const master = join(here, 'icon-1024.png');
const iconset = join(here, 'AppIcon.iconset');
const icns = join(resources, 'AppIcon.icns');

const sh = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });

const browser = await chromium.launch();
try {
  // 1. master 1024 render
  {
    const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
    await page.goto(pathToFileURL(join(here, 'icon.html')).href);
    await page.locator('#icon').screenshot({ path: master, omitBackground: true });
    await page.close();
  }

  // 2. menu-bar glyph at 1x and 2x
  for (const [scale, name] of [[1, 'menubar-22.png'], [2, 'menubar-44.png']]) {
    const page = await browser.newPage({ viewport: { width: 22, height: 22 }, deviceScaleFactor: scale });
    await page.goto(pathToFileURL(join(here, 'menubar.html')).href);
    await page.locator('#glyph').screenshot({ path: join(here, name), omitBackground: true });
    await page.close();
  }
} finally {
  await browser.close();
}

// 3. iconset via sips
rmSync(iconset, { recursive: true, force: true });
mkdirSync(iconset, { recursive: true });
const sizes = [
  ['icon_16x16.png', 16], ['icon_16x16@2x.png', 32],
  ['icon_32x32.png', 32], ['icon_32x32@2x.png', 64],
  ['icon_128x128.png', 128], ['icon_128x128@2x.png', 256],
  ['icon_256x256.png', 256], ['icon_256x256@2x.png', 512],
  ['icon_512x512.png', 512], ['icon_512x512@2x.png', 1024],
];
for (const [name, px] of sizes) {
  const out = join(iconset, name);
  if (px === 1024) copyFileSync(master, out);
  else execFileSync('sips', ['-z', String(px), String(px), master, '--out', out], { stdio: 'ignore' });
}
copyFileSync(join(iconset, 'icon_32x32.png'), join(here, 'preview-32.png'));

// 4. icns
sh('iconutil', ['-c', 'icns', iconset, '-o', icns]);
if (!existsSync(icns)) throw new Error('iconutil produced no output');
console.log(`wrote ${master}\nwrote ${icns}\nwrote ${join(here, 'menubar-22.png')} / menubar-44.png`);
