import assert from "node:assert/strict";
import { access, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadAllSources } from "../js/loader.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const baseUrl = process.env.SAGE_TEST_BASE ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run requirements.spec.mjs");
}

globalThis.fetch = (resource, init) => {
  const url = resource instanceof URL ? resource : new URL(String(resource), baseUrl);
  return nativeFetch(url, init);
};

async function runTest(name, testFn) {
  try {
    await testFn();
    console.log(`PASS ${name}`);
    return { name, passed: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.log(`FAIL ${name}: ${message}`);
    return { name, passed: false, message };
  }
}

async function testShellBrandingAndNoUpload() {
  const response = await nativeFetch(new URL("index.html", baseUrl));
  assert.equal(response.ok, true, "index.html should be served successfully");

  const html = await response.text();
  assert.match(html, /<title>SAGE<\/title>/, "browser title should contain SAGE");
  assert.match(html, /<h1 id="pageTitle">SAGE<\/h1>/, "page heading should show SAGE");
  assert.doesNotMatch(html, /type="file"/i, "the interface must not expose any file upload control");
  assert.doesNotMatch(html, /importInput/, "legacy import input should be removed from the HTML shell");
}

async function testRepoDataLayout() {
  await access(path.join(repoRoot, "data", "json", "day1.json"));
  await access(path.join(repoRoot, "data", "json", "day2.json"));
  await access(path.join(repoRoot, "data", "csv", ".gitkeep"));

  await assert.rejects(access(path.join(repoRoot, "rooms.json")), "legacy root day1 file should be absent");
  await assert.rejects(access(path.join(repoRoot, "room2.json")), "legacy root day2 file should be absent");
}

async function testMissingSourceResilience() {
  const sources = {
    sources: [
      { name: "missing-day", defaultDate: "2026-03-19" },
      { name: "day1", defaultDate: "2026-03-17" },
      { name: "day2", defaultDate: "2026-03-18" },
    ],
  };

  const result = await loadAllSources(sources);

  assert.equal(result.events.length, 72, "existing sources should still load when one configured source is missing");
  assert.equal(result.errors.length, 1, "a single missing source should report one warning entry");
  assert.match(result.errors[0], /data\/csv\/missing-day\.csv/, "error should mention the missing CSV path");
  assert.match(result.errors[0], /data\/json\/missing-day\.json/, "error should mention the missing JSON fallback path");
}

async function testMalformedCommittedCsvHandling() {
  const csvPath = path.join(repoRoot, "data", "csv", "day1.csv");
  const csvContents = [
    "date,start,end,team,vs,topics,location,type",
    "2026-03-17,09:00,09:50,ALL,,CSV Plenary,Auditorium,Plenary",
    "2026-03-17,10:00,11:10,Plenary PLM,PLM,CSV Objectives,,Plenary",
  ].join("\n");

  await writeFile(csvPath, csvContents, "utf8");

  try {
    const sources = JSON.parse(await readFile(path.join(repoRoot, "config", "sources.json"), "utf8"));
    const result = await loadAllSources(sources);

    assert.equal(result.events.length, 37, "valid committed CSV rows should load and invalid rows should be skipped");
    assert.equal(result.errors.length, 1, "one malformed committed CSV row should yield one warning");
    assert.match(result.errors[0], /Missing location/, "warning should explain why the malformed row was skipped");
    assert.equal(result.events.filter((event) => event.source === "data/csv/day1.csv").length, 1, "CSV should take precedence over JSON for the same source");
    assert.equal(result.events.some((event) => event.topics === "CSV Plenary"), true, "CSV-backed content should appear in the loaded events");
  } finally {
    await rm(csvPath, { force: true });
  }
}

const tests = [
  ["shell_shows_sage_and_hides_upload_control", testShellBrandingAndNoUpload],
  ["repo_uses_data_folder_layout", testRepoDataLayout],
  ["loadAllSources_continues_when_one_source_is_missing", testMissingSourceResilience],
  ["loadAllSources_prefers_csv_and_skips_invalid_committed_rows", testMalformedCommittedCsvHandling],
];

const results = [];
for (const [name, testFn] of tests) {
  results.push(await runTest(name, testFn));
}

const failed = results.filter((result) => !result.passed);
console.log(`SUMMARY total=${results.length} passed=${results.length - failed.length} failed=${failed.length}`);

if (failed.length > 0) {
  process.exitCode = 1;
}