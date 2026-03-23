import assert from "node:assert/strict";
import { readFile, rm, writeFile } from "node:fs/promises";
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

async function fetchJson(relativePath) {
  const response = await nativeFetch(new URL(relativePath, baseUrl));
  assert.equal(response.ok, true, `Expected ${relativePath} to return HTTP 200`);
  return response.json();
}

async function withTemporaryFile(filePath, content, testFn) {
  const originalContent = await readFile(filePath, "utf8").catch(() => null);
  await writeFile(filePath, content, "utf8");

  try {
    await testFn();
  } finally {
    if (originalContent === null) {
      await rm(filePath, { force: true });
    } else {
      await writeFile(filePath, originalContent, "utf8");
    }
  }
}

await runTest("loader ignores extra date files that are not referenced in sources config", async () => {
  const sources = await fetchJson("config/sources.json");
  const extraFilePath = path.join(workspaceRoot, "data", "json", "2026-03-19.json");
  const extraRecords = [
    {
      time: "08:00-08:30",
      location: "Ignored Room",
      topics: "Should Not Load",
      team: "Ignored Team",
      vs: "PLM",
      type: "Breakout",
    },
  ];

  await withTemporaryFile(extraFilePath, `${JSON.stringify(extraRecords, null, 2)}\n`, async () => {
    const result = await loadAllSources(sources);

    assert.equal(result.errors.length, 0);
    assert.ok(result.events.every((event) => event.date !== "2026-03-19"));
    assert.ok(result.events.every((event) => event.topics !== "Should Not Load"));
  });
});

await runTest("loader prefers a configured CSV file over the matching date-named JSON file", async () => {
  const sources = await fetchJson("config/sources.json");
  const csvPath = path.join(workspaceRoot, "data", "csv", "2026-03-17.csv");
  const csvContent = [
    "time,location,topics,name,value stream,teams,type",
    "09:00 - 09:50,Auditorium,CSV Override,Overall PI Plenary,ALL,,Plenary",
  ].join("\n");

  await withTemporaryFile(csvPath, csvContent, async () => {
    const baselineDay2Count = (await loadAllSources(sources)).events.filter((event) => event.date === "2026-03-18").length;
    const result = await loadAllSources(sources);

    assert.equal(result.errors.length, 0);
    assert.equal(result.events.length, 1 + baselineDay2Count);
    assert.ok(result.events.some((event) => event.name === "Overall PI Plenary" && event.teams.length === 0 && event.source === "data/csv/2026-03-17.csv"));
    assert.ok(result.events.every((event) => !(event.date === "2026-03-17" && event.source === "data/json/2026-03-17.json")));
  });
});

await runTest("missing-source errors name the attempted date-based files for a logical label", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources({
    sources: [
      ...sources.sources,
      { label: "day3", defaultDate: "2026-03-19" },
    ],
  });

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /data\/csv\/2026-03-19\.csv/);
  assert.match(result.errors[0], /data\/json\/2026-03-19\.json/);
  assert.doesNotMatch(result.errors[0], /Failed to load source day3/);
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