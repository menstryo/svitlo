// Builds static JSON for GitHub Pages: public/regions.json, public/schedule/<id>.json
import fs from "fs";
import path from "path";
import { REGIONS, buildSchedule } from "../worker/src/index.js";

const out = path.resolve("public");
fs.mkdirSync(path.join(out, "schedule"), { recursive: true });

const ok = [];
for (const reg of REGIONS) {
  try {
    const data = await buildSchedule(reg);
    fs.writeFileSync(path.join(out, "schedule", `${reg.id}.json`), JSON.stringify(data));
    ok.push({ id: reg.id, name: reg.name });
    console.log("ok  ", reg.id, data.queues.length, "queues");
  } catch (e) {
    console.log("FAIL", reg.id, e.message);
  }
}
fs.writeFileSync(path.join(out, "regions.json"), JSON.stringify({ regions: ok, generated: new Date().toISOString() }));
fs.writeFileSync(path.join(out, ".nojekyll"), "");
fs.copyFileSync(path.resolve("site/index.html"), path.join(out, "index.html"));
if (fs.existsSync("Svitlo.ipa")) fs.copyFileSync("Svitlo.ipa", path.join(out, "Svitlo.ipa"));
if (ok.length === 0) process.exit(1);
