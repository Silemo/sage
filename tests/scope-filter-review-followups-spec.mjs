import assert from "node:assert/strict";
import { readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadAllSources, normalizeRecord } from "../js/loader.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const workspaceRoot = path.resolve(__dirname, "..");
const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run scope-filter-review-followups-spec.mjs");
}

globalThis.fetch = (resource, init) => {
  const url = resource instanceof URL ? resource : new URL(String(resource), baseUrl);
  return nativeFetch(url, init);
};

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

await runTest("configured day-two source prefers CSV while legacy JSON still normalizes into the current contract", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const dayTwoEvents = result.events.filter((event) => event.date === "2026-03-18");
  assert.ok(dayTwoEvents.length > 0);
  assert.equal(dayTwoEvents.every((event) => event.source === "data/csv/2026-03-18.csv"), true);
  assert.ok(dayTwoEvents.some((event) => event.name === "VS PLM Plenary"));

  const legacyJsonRecords = await fetchJson("data/json/2026-03-18.json");
  const normalizedResults = legacyJsonRecords
    .map((record) => normalizeRecord(record, "data/json/2026-03-18.json", "2026-03-18"));

  assert.equal(normalizedResults.every((normalizedResult) => normalizedResult.errors.length === 0), true);

  const normalizedRecords = normalizedResults
    .map((normalizedResult) => normalizedResult.record)
    .filter((record) => record);

  assert.ok(normalizedRecords.some((record) => record.name === "MSFT" && record.teams.includes("MSFT")));
  assert.ok(normalizedRecords.some((record) => record.name === "Plenary Exp Runway" && record.vs === "Exp RW"));
});

await runTest("malformed day-one CSV does not hide legitimate day-two VS PLM plenary events", async () => {
  const malformedCsv = [
    "time,location,topics,name,value stream,teams,type",
    "09:00 - 09:50,Auditorium,CSV Plenary,Overall PI Plenary,ALL,,Plenary",
    "10:00 - 11:10,,Missing Location,VS PLM Plenary,PLM,Marvels,Plenary",
  ].join("\n");

  await withTemporaryCsv("2026-03-17", malformedCsv, async () => {
    const sources = await fetchJson("config/sources.json");
    const result = await loadAllSources(sources);

    assert.equal(result.errors.length, 1);

    const dayOneEvents = result.events.filter((event) => event.date === "2026-03-17");
    const dayTwoPlmPlenaries = result.events.filter(
      (event) => event.date === "2026-03-18" && event.name === "VS PLM Plenary",
    );

    assert.deepEqual(dayOneEvents.map((event) => event.name), ["Overall PI Plenary"]);
    assert.ok(dayTwoPlmPlenaries.length > 0);
    assert.equal(dayTwoPlmPlenaries.every((event) => event.source === "data/csv/2026-03-18.csv"), true);
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
if (failCount > 0) {
  process.exitCode = 1;
}