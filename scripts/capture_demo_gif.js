const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");
const { chromium } = require("playwright");

const DEMO_DIR = path.join(__dirname, "..", "demo");
const INDEX_HTML = path.join(DEMO_DIR, "index.html");
const VIDEO_DIR = path.join(__dirname, "..", "tmp-video");
const OUTPUT_GIF = path.join(DEMO_DIR, "demo.gif");
const PALETTE_PATH = path.join(VIDEO_DIR, "palette.png");
const VIEWPORT = { width: 1280, height: 720 };
const GIF_SIZE = { width: 960, height: 540 };
const DURATION_MS = 20000;
const GIF_FPS = 12;

async function main() {
  if (!fs.existsSync(INDEX_HTML)) {
    console.error("Demo not found:", INDEX_HTML);
    process.exit(1);
  }
  try {
    execSync("ffmpeg -version", { stdio: "ignore" });
  } catch (_) {
    console.error("ffmpeg is required. Install with: brew install ffmpeg");
    process.exit(1);
  }

  fs.mkdirSync(VIDEO_DIR, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: VIEWPORT,
    recordVideo: { dir: VIDEO_DIR, size: VIEWPORT },
  });
  const page = await context.newPage();
  const video = page.video();
  await page.goto("file://" + path.resolve(INDEX_HTML) + "?play=1", {
    waitUntil: "domcontentloaded",
  });
  await page.waitForTimeout(DURATION_MS);
  await context.close();
  const videoPath = await video.path();
  await browser.close();

  const w = GIF_SIZE.width;
  const h = GIF_SIZE.height;
  // Two-pass GIF encoding (palettegen/paletteuse) at smaller size for lower file size.
  execSync(
    [
      "ffmpeg",
      "-y",
      "-i",
      `"${videoPath}"`,
      "-vf",
      `"fps=${GIF_FPS},scale=${w}:${h}:flags=lanczos,palettegen=stats_mode=diff:max_colors=192"`,
      `"${PALETTE_PATH}"`,
    ].join(" "),
    { stdio: "inherit" }
  );

  execSync(
    [
      "ffmpeg",
      "-y",
      "-i",
      `"${videoPath}"`,
      "-i",
      `"${PALETTE_PATH}"`,
      "-lavfi",
      `"fps=${GIF_FPS},scale=${w}:${h}:flags=lanczos[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle"`,
      `"${OUTPUT_GIF}"`,
    ].join(" "),
    { stdio: "inherit" }
  );

  fs.rmSync(VIDEO_DIR, { recursive: true, force: true });
  console.log("Wrote", OUTPUT_GIF);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
