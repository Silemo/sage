import assert from "node:assert/strict";

import { createEventId, normalizeRecord } from "../js/loader.js";
import { buildHierarchy, filterEvents, isGlobalPlenary } from "../js/filter.js";
import { createRoomCard, getEventColor, renderLegend } from "../js/renderer.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
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
    replaceChildren(...nodes) {
      this.children = [...nodes];
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

async function testShellBrandingAndNoUpload() {
  const response = await nativeFetch(new URL("index.html", baseUrl));
  assert.equal(response.ok, true, "index.html should be served successfully");

  const html = await response.text();
  assert.match(html, /<title>SAGE<\/title>/, "browser title should contain SAGE");
  assert.match(html, /<h1 id="pageTitle">SAGE<\/h1>/, "page heading should show SAGE");
  assert.doesNotMatch(html, /type="file"/i, "the interface must not expose any file upload control");
  assert.doesNotMatch(html, /importInput/, "legacy import input should be removed from the HTML shell");
}

async function testNormalizeRecordSupportsCsvAndLegacyJson() {
  const csvResult = normalizeRecord({
    time: "10:00 - 11:30",
    location: "2C",
    topics: "PI Objectives",
    name: "VS PLM Plenary",
    "value stream": "PLM",
    teams: "Marvels,Avengers",
    type: "Plenary",
  }, "data/csv/2026-03-17.csv", "2026-03-17");

  assert.equal(csvResult.errors.length, 0);
  assert.equal(csvResult.record?.name, "VS PLM Plenary");
  assert.deepEqual(csvResult.record?.teams, ["Marvels", "Avengers"]);
  assert.equal(csvResult.record?.vs, "PLM");
  assert.equal(csvResult.record?.date, "2026-03-17");

  const legacyResult = normalizeRecord({
    time: "11:30-16:00",
    location: "1B",
    topics: "RPM",
    team: "Marvels",
    vs: "PLM",
    type: "Breakout",
  }, "data/json/2026-03-18.json", "2026-03-18");

  assert.equal(legacyResult.errors.length, 0);
  assert.equal(legacyResult.record?.name, "Marvels");
  assert.deepEqual(legacyResult.record?.teams, ["Marvels"]);
  assert.equal(legacyResult.record?.vs, "PLM");

  const teamlessResult = normalizeRecord({
    time: "09:45 - 10:00",
    location: "Lobby",
    topics: "Small talk",
    name: "Coffee break",
    "value stream": "ALL",
    teams: "",
    type: "Coffee",
  }, "data/csv/2026-03-17.csv", "2026-03-17");

  assert.equal(teamlessResult.errors.length, 0);
  assert.deepEqual(teamlessResult.record?.teams, []);
}

async function testHierarchyAndTeamFilteringFollowNewContract() {
  const events = [
    {
      date: "2026-03-17",
      start: "08:55",
      end: "09:45",
      name: "Overall PI Plenary",
      teams: [],
      vs: "ALL",
      topics: "PI Objectives",
      location: "Auditorium",
      type: "Plenary",
    },
    {
      date: "2026-03-17",
      start: "10:00",
      end: "11:30",
      name: "VS PLM Plenary",
      teams: ["Marvels", "Avengers"],
      vs: "PLM",
      topics: "PI Objectives",
      location: "2C",
      type: "Plenary",
    },
    {
      date: "2026-03-17",
      start: "11:30",
      end: "16:00",
      name: "Marvels",
      teams: ["Marvels"],
      vs: "PLM",
      topics: "RPM",
      location: "1B",
      type: "Breakout",
    },
    {
      date: "2026-03-17",
      start: "11:30",
      end: "16:00",
      name: "Transformers",
      teams: ["Transformers"],
      vs: "PLM",
      topics: "RPM",
      location: "1E",
      type: "Breakout",
    },
    {
      date: "2026-03-17",
      start: "09:45",
      end: "10:00",
      name: "Coffee break",
      teams: [],
      vs: "ALL",
      topics: "Small talk",
      location: "Lobby",
      type: "Coffee",
    },
  ];

  const hierarchy = buildHierarchy(events);
  assert.deepEqual(hierarchy.valueStreams.PLM, ["Avengers", "Marvels", "Transformers"]);
  assert.equal(isGlobalPlenary(events[0]), true);

  const filtered = filterEvents(events, {
    date: "2026-03-17",
    mode: "team",
    value: "Marvels",
    search: "",
  });

  assert.deepEqual(
    filtered.map((event) => event.name),
    ["Overall PI Plenary", "Coffee break", "VS PLM Plenary", "Marvels"],
  );
  assert.equal(filtered.some((event) => event.name === "Transformers"), false);
}

async function testEventIdAndRendererUseMeetingName() {
  const recordA = {
    date: "2026-03-17",
    start: "11:30",
    end: "16:00",
    name: "Marvels",
    location: "1B",
    topics: "RPM",
  };
  const recordB = {
    ...recordA,
    name: "Transformers",
  };

  assert.notEqual(createEventId(recordA), createEventId(recordB));

  const restoreDom = installMinimalDom();
  try {
    const card = createRoomCard({
      start: "11:30",
      end: "16:00",
      name: "Marvels Planning",
      teams: ["Marvels"],
      location: "1B",
      topics: "RPM",
      vs: "PLM",
      type: "Breakout",
    }, {
      PLM: { bg: "#fff", border: "#000" },
      _default: { bg: "#fff", border: "#000" },
    });

    assert.equal(card.children[1].textContent, "Marvels Planning");
  } finally {
    restoreDom();
  }
}

async function testLegendAndColorUseValueStreamOnly() {
  const restoreDom = installMinimalDom();

  try {
    const colorMap = {
      ALL: { bg: "#ccc", border: "#111" },
      PLM: { bg: "#def", border: "#123" },
      _default: { bg: "#fff", border: "#999" },
    };

    assert.deepEqual(
      getEventColor({ vs: "ALL", type: "Plenary" }, colorMap),
      colorMap.ALL,
    );
    assert.deepEqual(
      getEventColor({ vs: "" }, colorMap),
      colorMap._default,
    );
    assert.deepEqual(
      getEventColor({ vs: "UNKNOWN" }, colorMap),
      colorMap._default,
    );

    const container = {
      children: [],
      replaceChildren(...nodes) {
        this.children = [...nodes];
      },
      appendChild(node) {
        this.children.push(node);
      },
    };

    renderLegend(container, colorMap, [
      { name: "Overall PI Plenary", vs: "ALL", type: "Plenary" },
      { name: "Coffee break", vs: "ALL", type: "Coffee" },
      { name: "PLM Planning", vs: "PLM", type: "Breakout" },
      { name: "Misconfigured", vs: "", type: "Breakout" },
    ]);

    const legendLabels = container.children.map((item) => item.children[1]?.textContent);
    assert.deepEqual(legendLabels, ["ALL", "PLM"]);
    assert.equal(legendLabels.filter((label) => label === "ALL").length, 1);
    assert.equal(legendLabels.includes(""), false);
  } finally {
    restoreDom();
  }
}

async function testRendererIgnoresTypeWhilePlenaryFilterStillUsesType() {
  const colorMap = {
    ALL: { bg: "#ccc", border: "#111" },
    PLM: { bg: "#def", border: "#123" },
    _default: { bg: "#fff", border: "#999" },
  };

  const events = [
    {
      date: "2026-03-17",
      start: "08:55",
      end: "09:45",
      name: "Overall PI Plenary",
      teams: [],
      vs: "ALL",
      topics: "PI Objectives",
      location: "Auditorium",
      type: "Plenary",
    },
    {
      date: "2026-03-17",
      start: "09:45",
      end: "10:00",
      name: "Coffee break",
      teams: [],
      vs: "ALL",
      topics: "Small talk",
      location: "Lobby",
      type: "Coffee",
    },
  ];

  assert.deepEqual(getEventColor(events[0], colorMap), colorMap.ALL);
  assert.deepEqual(getEventColor(events[1], colorMap), colorMap.ALL);

  const plenaryOnly = filterEvents(events, {
    date: "2026-03-17",
    mode: "plenary",
    value: "",
    search: "",
  });

  assert.deepEqual(plenaryOnly.map((event) => event.name), ["Overall PI Plenary"]);
}

async function testShippedColorConfigKeepsDefaultFallbackAndDropsPlenaryAlias() {
  const colorMap = await fetchJson("config/colors.json");

  assert.deepEqual(colorMap.ALL, {
    bg: "#ECEFF1",
    border: "#455A64",
  });
  assert.deepEqual(colorMap._default, {
    bg: "#FFFFFF",
    border: "#9E9E9E",
  });
  assert.equal("_plenary" in colorMap, false);
  assert.notDeepEqual(colorMap.ALL, colorMap._default);
}

const tests = [
  ["shell_shows_sage_and_hides_upload_control", testShellBrandingAndNoUpload],
  ["normalizeRecord_supports_new_csv_and_legacy_json_contracts", testNormalizeRecordSupportsCsvAndLegacyJson],
  ["hierarchy_and_team_filter_follow_name_and_teams_rules", testHierarchyAndTeamFilteringFollowNewContract],
  ["event_id_and_renderer_use_meeting_name", testEventIdAndRendererUseMeetingName],
  ["legend_and_colors_follow_value_stream_contract", testLegendAndColorUseValueStreamOnly],
  ["renderer_colors_ignore_type_but_plenary_filter_does_not", testRendererIgnoresTypeWhilePlenaryFilterStillUsesType],
  ["shipped_color_config_keeps_default_fallback_and_no_plenary_alias", testShippedColorConfigKeepsDefaultFallbackAndDropsPlenaryAlias],
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