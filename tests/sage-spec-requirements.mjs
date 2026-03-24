import assert from "node:assert/strict";
import { access, readFile, rm, writeFile } from "node:fs/promises";
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

const { loadAllSources, normalizeRecord } = await import("../js/loader.js");

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
  const originalContent = await readFile(csvPath, "utf8").catch(() => null);

  await writeFile(csvPath, content, "utf8");
  try {
    await testFn();
  } finally {
    if (originalContent === null) {
      await rm(csvPath, { force: true });
    } else {
      await writeFile(csvPath, originalContent, "utf8");
    }
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

await runTest("loader accepts committed CSV data and keeps legacy JSON fallback compatible", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);
  assert.ok(result.events.length > 0);
  const day1CsvEvents = result.events.filter((event) => event.source === "data/csv/2026-03-17.csv");
  const day2CsvEvents = result.events.filter((event) => event.source === "data/csv/2026-03-18.csv");

  assert.ok(day1CsvEvents.length > 0);
  assert.ok(day2CsvEvents.length > 0);
  assert.ok(day1CsvEvents.every((event) => typeof event.name === "string" && Array.isArray(event.teams)));
  assert.ok(day2CsvEvents.every((event) => typeof event.name === "string" && Array.isArray(event.teams)));
  assert.deepEqual(
    [...new Set(result.events.map((event) => event.date))].sort(),
    ["2026-03-17", "2026-03-18"],
  );

  const legacyJsonRecords = await fetchJson("data/json/2026-03-18.json");
  const normalizedJsonResults = legacyJsonRecords
    .map((record) => normalizeRecord(record, "data/json/2026-03-18.json", "2026-03-18"));

  normalizedJsonResults.forEach((normalizedResult) => {
    assert.equal(normalizedResult.errors.length, 0);
    assert.equal(typeof normalizedResult.record?.name, "string");
    assert.equal(Array.isArray(normalizedResult.record?.teams), true);
  });
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
    "time,location,topics,name,value stream,teams,type",
    "09:00 - 09:50,Auditorium,CSV Plenary,Overall PI Plenary,ALL,,Plenary",
    "10:00 - 11:10,,Missing Location,VS PLM Plenary,PLM,Marvels,Plenary",
  ].join("\n");

  await withTemporaryCsv("2026-03-17", malformedCsv, async () => {
    const sources = await fetchJson("config/sources.json");
    const baselineDay2Count = (await loadAllSources(sources)).events.filter((event) => event.date === "2026-03-18").length;
    const result = await loadAllSources(sources);
    const mutatedDay1Events = result.events.filter((event) => event.date === "2026-03-17");

    assert.equal(result.events.length, 1 + baselineDay2Count);
    assert.equal(result.errors.length, 1);
    assert.ok(result.events.some((event) => event.name === "Overall PI Plenary" && event.teams.length === 0));
    assert.ok(result.events.some((event) => event.date === "2026-03-18"));
    assert.ok(mutatedDay1Events.every((event) => event.name !== "VS PLM Plenary"));
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