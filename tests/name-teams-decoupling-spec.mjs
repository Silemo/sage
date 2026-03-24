import assert from "node:assert/strict";

import { loadAllSources } from "../js/loader.js";
import { buildHierarchy, filterEvents, isGlobalPlenary, isVsPlenary } from "../js/filter.js";
import { createRoomCard } from "../js/renderer.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run name-teams-decoupling-spec.mjs");
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

function installMinimalDom() {
  const previousDocument = globalThis.document;

  const createElement = (tagName) => ({
    tagName,
    className: "",
    textContent: "",
    children: [],
    style: {
      values: {},
      setProperty(name, value) {
        this.values[name] = value;
      },
    },
    append(...nodes) {
      this.children.push(...nodes);
    },
    appendChild(node) {
      this.children.push(node);
    },
  });

  globalThis.document = {
    createElement,
    createTextNode(text) {
      return { nodeType: "text", textContent: text };
    },
  };

  return () => {
    globalThis.document = previousDocument;
  };
}

function collectText(node) {
  if (!node || typeof node !== "object") {
    return "";
  }

  const ownText = typeof node.textContent === "string" ? node.textContent : "";
  const childText = Array.isArray(node.children)
    ? node.children.map((child) => collectText(child)).join(" ")
    : "";
  return `${ownText} ${childText}`.trim();
}

await runTest("team filter includes teamless activities and matching value-stream plenaries for committed CSV data", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const filtered = filterEvents(result.events, {
    date: "2026-03-17",
    mode: "team",
    value: "Marvels",
    search: "",
  });

  const names = filtered.map((event) => event.name);
  assert.ok(names.includes("Overall PI Plenary"));
  assert.ok(names.includes("Coffee break"));
  assert.ok(names.includes("Lunch"));
  assert.ok(names.includes("Marvels"));
  assert.equal(names.filter((name) => name === "VS PLM Plenary").length, 3);
  assert.equal(names.includes("Transformers"), false);

  filtered.forEach((event) => {
    const isAllowed = isGlobalPlenary(event)
      || isVsPlenary(event, "PLM")
      || event.teams.includes("Marvels")
      || event.teams.length === 0;

    assert.equal(isAllowed, true, `Unexpected event in team filter result: ${event.name}`);
  });
});

await runTest("hierarchy groups only teams under their value streams for committed CSV data", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const hierarchy = buildHierarchy(result.events);
  assert.ok(hierarchy.valueStreams.PLM.includes("Marvels"));
  assert.ok(hierarchy.valueStreams.PLM.includes("Transformers"));
  assert.ok(hierarchy.valueStreams.MON.includes("Alpha"));
  assert.equal(hierarchy.valueStreams.PLM.includes("Overall PI Plenary"), false);
  assert.equal(hierarchy.valueStreams.PLM.includes("Coffee break"), false);
});

await runTest("renderer shows meeting name and hides filter-only teams", async () => {
  const restoreDom = installMinimalDom();

  try {
    const card = createRoomCard({
      start: "10:00",
      end: "11:30",
      name: "VS PLM Plenary",
      teams: ["Marvels", "Avengers"],
      location: "2C",
      topics: "PI Objectives",
      vs: "PLM",
      type: "Plenary",
    }, {
      PLM: { bg: "#fff", border: "#000" },
      _default: { bg: "#fff", border: "#000" },
      _plenary: { bg: "#fff", border: "#000" },
    });

    assert.equal(card.children[1].textContent, "VS PLM Plenary");

    const cardText = collectText(card);
    assert.equal(cardText.includes("Marvels"), false);
    assert.equal(cardText.includes("Avengers"), false);
  } finally {
    restoreDom();
  }
});

await runTest("legacy JSON day still supports team filtering through fallback team normalization", async () => {
  const sources = await fetchJson("config/sources.json");
  const result = await loadAllSources(sources);

  assert.equal(result.errors.length, 0);

  const filtered = filterEvents(result.events, {
    date: "2026-03-18",
    mode: "team",
    value: "Core Team",
    search: "",
  });

  assert.ok(filtered.some((event) => event.name === "Core Team" && event.teams.includes("Core Team")));
  assert.ok(filtered.some((event) => isGlobalPlenary(event)));
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