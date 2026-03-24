import assert from "node:assert/strict";

import { loadAllSources } from "../js/loader.js";
import { filterEvents } from "../js/filter.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run scope-filter-all-events-spec.mjs");
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

await runTest("plenary scope shows all shared ALL events for day two and excludes VS-specific plenaries", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const filtered = filterEvents(result.events, {
    date: "2026-03-18",
    mode: "plenary",
    value: "",
    search: "",
  });

  assert.deepEqual(
    filtered.map((event) => event.name),
    ["Lunch", "Coffee break", "Overall PI Plenary", "Drinks and nibbles"],
  );
  assert.equal(filtered.every((event) => event.vs === "ALL"), true);
  assert.equal(filtered.some((event) => event.name === "VS MON Plenary"), false);
});

await runTest("value-stream scope keeps shared ALL events visible after search filtering", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const filtered = filterEvents(result.events, {
    date: "2026-03-18",
    mode: "vs",
    value: "MON",
    search: "good",
  });

  assert.deepEqual(
    filtered.map((event) => event.name),
    ["Lunch", "Drinks and nibbles"],
  );
  assert.equal(filtered.every((event) => event.vs === "ALL"), true);
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