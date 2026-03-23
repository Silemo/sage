import assert from "node:assert/strict";
import { access, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const workspaceRoot = path.resolve(__dirname, "..");
const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";

const nativeFetch = globalThis.fetch;
globalThis.fetch = (resource, init) => {
  if (typeof resource === "string") {
    return nativeFetch(new URL(resource, baseUrl), init);
  }

  if (resource instanceof URL) {
    return nativeFetch(new URL(resource.toString(), baseUrl), init);
  }

  return nativeFetch(resource, init);
};

const { loadAllSources } = await import("../js/loader.js");

const results = [];

async function runTest(name, testFn) {
  try {
    await testFn();
    results.push({ name, status: "PASS" });
  } catch (error) {
    results.push({
      name,
      status: "FAIL",
      details: error instanceof Error ? error.message : String(error),
    });
  }
}

async function fetchText(relativePath) {
  const response = await nativeFetch(new URL(relativePath, baseUrl));
  assert.equal(response.ok, true, `Expected ${relativePath} to return HTTP 200`);
  return response.text();
}

async function fetchJson(relativePath) {
  const response = await nativeFetch(new URL(relativePath, baseUrl));
  assert.equal(response.ok, true, `Expected ${relativePath} to return HTTP 200`);
  return response.json();
}

async function withTemporaryCsv(fileStem, content, testFn) {
  const csvPath = path.join(workspaceRoot, "data", "csv", `${fileStem}.csv`);

  await writeFile(csvPath, content, "utf8");
  try {
    await testFn();
  } finally {
    await rm(csvPath, { force: true });
  }
}

await runTest("shipped shell shows SAGE branding and no upload control", async () => {
  const indexHtml = await fetchText("index.html");

  assert.match(indexHtml, /<title>SAGE<\/title>/);
  assert.match(indexHtml, /<h1 id="pageTitle">SAGE<\/h1>/);
  assert.doesNotMatch(indexHtml, /id="importInput"/);
  assert.doesNotMatch(indexHtml, /type="file"/);
});

await runTest("repo uses canonical data folders and logical source names", async () => {
  await access(path.join(workspaceRoot, "data", "csv"));
  await access(path.join(workspaceRoot, "data", "json"));

  const sources = await fetchJson("config/sources.json");
  assert.ok(Array.isArray(sources.sources));
  assert.deepEqual(
    sources.sources.map((source) => Object.keys(source).sort()),
    [
      ["defaultDate", "label"],
      ["defaultDate", "label"],
    ],
  );
  assert.deepEqual(
    sources.sources.map((source) => source.label),
    ["day1", "day2"],
  );
});

await runTest("loader falls back to committed JSON when CSV files are absent", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);
  assert.ok(result.events.length > 0);
  assert.ok(result.events.every((event) => event.source.startsWith("data/json/")));
  assert.deepEqual(
    [...new Set(result.events.map((event) => event.date))].sort(),
    ["2026-03-17", "2026-03-18"],
  );
});

await runTest("loader continues loading later sources when one source is missing", async () => {
  const sources = await fetchJson("config/sources.json");
  const baselineResult = await loadAllSources(sources);
  const augmentedSources = {
    sources: [
      sources.sources[0],
      { label: "missing-day", defaultDate: "2026-03-19" },
      sources.sources[1],
    ],
  };
  const result = await loadAllSources(augmentedSources);

  assert.equal(result.events.length, baselineResult.events.length);
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /data\/csv\/2026-03-19\.csv/);
  assert.match(result.errors[0], /data\/json\/2026-03-19\.json/);
  assert.ok(result.events.some((event) => event.date === "2026-03-18"));
});

await runTest("loader skips malformed committed CSV rows without aborting the schedule", async () => {
  const malformedCsv = [
    "date,start,end,team,vs,topics,location,type",
    "2026-03-17,09:00,09:50,ALL,,CSV Plenary,Auditorium,Plenary",
    "2026-03-17,10:00,11:10,Plenary PLM,PLM,Missing Location,,Plenary",
  ].join("\n");

  await withTemporaryCsv("2026-03-17", malformedCsv, async () => {
    const sources = await fetchJson("config/sources.json");
    const baselineDay2Count = (await loadAllSources(sources)).events.filter((event) => event.date === "2026-03-18").length;
    const result = await loadAllSources(sources);

    assert.equal(result.events.length, 1 + baselineDay2Count);
    assert.equal(result.errors.length, 1);
    assert.ok(result.events.some((event) => event.topics === "CSV Plenary"));
    assert.ok(result.events.some((event) => event.date === "2026-03-18"));
    assert.ok(result.events.every((event) => event.topics !== "Missing Location"));
    assert.match(result.errors[0], /Missing location/);
  });
});

const passCount = results.filter((result) => result.status === "PASS").length;
const failCount = results.filter((result) => result.status === "FAIL").length;
console.log(`PASS ${passCount}/${results.length}`);
for (const result of results) {
  if (result.details) {
    console.log(`${result.status}: ${result.name} -- ${result.details}`);
  } else {
    console.log(`${result.status}: ${result.name}`);
  }
}
process.exit(failCount > 0 ? 1 : 0);