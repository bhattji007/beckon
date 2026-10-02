import { chromium } from 'playwright';
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync, readdirSync, existsSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { homedir } from 'node:os';

const FPS = 30;
const args = process.argv.slice(2);
const files = args.length ? args : readdirSync('drafts').filter(f=>f.endsWith('.html')).map(f=>'drafts/'+f);
import ffmpegStatic from 'ffmpeg-static';
const ffmpeg = ffmpegStatic;

const browser = await chromium.launch();
for (const file of files) {
  const name = basename(file, '.html');
  const frames = resolve('render/frames', name);
  rmSync(frames, { recursive: true, force: true }); mkdirSync(frames, { recursive: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await page.goto('file://' + resolve(file));
  await page.waitForFunction(() => typeof window.__seek === 'function');
  await page.evaluate(() => document.fonts.ready);
  const duration = await page.evaluate(() => window.__duration);
  const n = Math.ceil(duration / 1000 * FPS);
  const t0 = Date.now();
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => window.__seek(t), i * 1000 / FPS);
    await page.screenshot({ path: `${frames}/${String(i).padStart(5,'0')}.jpg`, type: 'jpeg', quality: 92 });
    if (i % 60 === 0) process.stdout.write(`\r${name}: ${i}/${n} frames`);
  }
  console.log(`\r${name}: ${n} frames in ${((Date.now()-t0)/1000).toFixed(1)}s`);
  await page.close();
  const out = resolve('videos', name + '.mp4');
  const r = spawnSync(ffmpeg, ['-y','-framerate', String(FPS), '-i', `${frames}/%05d.jpg`, '-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart', out], { stdio: 'pipe' });
  if (r.status !== 0) { console.error(r.stderr.toString().slice(-800)); process.exit(1); }
  // contact sheet for review: 12 evenly spaced frames
  const step = Math.max(1, Math.floor(n / 12));
  spawnSync(ffmpeg, ['-y','-i', `${frames}/%05d.jpg`, '-vf', `select='not(mod(n\\,${step}))',scale=480:-1,tile=3x4`, '-frames:v','1', resolve('render', name + '-sheet.jpg')], { stdio: 'pipe' });
  console.log('wrote', out);
}
await browser.close();
