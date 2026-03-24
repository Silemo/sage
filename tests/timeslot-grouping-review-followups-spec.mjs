import assert from "node:assert/strict";

import { loadAllSources } from "../js/loader.js";
import { filterEvents } from "../js/filter.js";
import { renderTimeslotGroups } from "../js/renderer.js";
import { findCurrentBucketIndex, groupEventsByTimeslot } from "../js/timeslot.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run timeslot-grouping-review-followups-spec.mjs");
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

function createStyle() {
  return {
    values: {},
    setProperty(name, value) {
      this.values[name] = value;
    },
  };
}

class FakeFragment {
  constructor() {
    this.children = [];
    this.parentNode = null;
  }

  appendChild(node) {
    if (node && typeof node === "object") {
      node.parentNode = this;
    }
    this.children.push(node);
    return node;
  }
}

function matchesSelector(element, selector) {
  if (!element || element.nodeType === "text") {
    return false;
  }

  const classNames = String(element.className ?? "").split(/\s+/).filter(Boolean);
  const hasClass = (className) => classNames.includes(className);

  if (selector === ".room-card") {
    return hasClass("room-card");
  }

  if (selector === ".timeslot-group") {
    return hasClass("timeslot-group");
  }

  if (selector === ".timeslot-header") {
    return hasClass("timeslot-header");
  }

  if (selector === ".timeslot-toggle") {
    return hasClass("timeslot-toggle");
  }

  if (selector === ".timeslot-now") {
    return hasClass("timeslot-now");
  }

  if (selector === ".timeslot-cards") {
    return hasClass("timeslot-cards");
  }

  if (selector === ".timeslot-label") {
    return hasClass("timeslot-label");
  }

  if (selector === ".legend-item[data-vs]") {
    return hasClass("legend-item") && String(element.dataset?.vs ?? "") !== "";
  }

  if (selector === "button[data-date]") {
    return element.tagName === "BUTTON" && String(element.dataset?.date ?? "") !== "";
  }

  return false;
}

class FakeElement {
  constructor(tagName) {
    this.tagName = String(tagName).toUpperCase();
    this.className = "";
    this.textContent = "";
    this.children = [];
    this.parentNode = null;
    this.dataset = {};
    this.style = createStyle();
    this.listeners = new Map();
    this.hidden = false;
    this.value = "";
    this.type = "";
    this.label = "";
    this.id = "";
    this.tabIndex = 0;
    this.attributes = new Map();
    this.focused = false;
    this.scrolled = false;
    this.classList = {
      add: (...tokens) => {
        const values = new Set(String(this.className).split(/\s+/).filter(Boolean));
        tokens.forEach((token) => values.add(token));
        this.className = [...values].join(" ");
      },
      remove: (...tokens) => {
        const values = String(this.className).split(/\s+/).filter((token) => token && !tokens.includes(token));
        this.className = values.join(" ");
      },
      toggle: (token, force) => {
        const values = new Set(String(this.className).split(/\s+/).filter(Boolean));
        const shouldAdd = force === undefined ? !values.has(token) : Boolean(force);
        if (shouldAdd) {
          values.add(token);
        } else {
          values.delete(token);
        }
        this.className = [...values].join(" ");
        return shouldAdd;
      },
      contains: (token) => String(this.className).split(/\s+/).filter(Boolean).includes(token),
    };
  }

  append(...nodes) {
    nodes.forEach((node) => this.appendChild(node));
  }

  appendChild(node) {
    if (node instanceof FakeFragment) {
      node.children.forEach((child) => this.appendChild(child));
      node.children = [];
      return node;
    }

    if (node && typeof node === "object") {
      node.parentNode = this;
    }
    this.children.push(node);
    return node;
  }

  replaceChildren(...nodes) {
    this.children.forEach((node) => {
      if (node && typeof node === "object") {
        node.parentNode = null;
      }
    });
    this.children = [];
    nodes.forEach((node) => this.appendChild(node));
  }

  insertBefore(node, target) {
    if (!target) {
      return this.appendChild(node);
    }

    const index = this.children.indexOf(target);
    if (index === -1) {
      return this.appendChild(node);
    }

    if (node && typeof node === "object") {
      node.parentNode = this;
    }
    this.children.splice(index, 0, node);
    return node;
  }

  addEventListener(type, callback) {
    this.listeners.set(type, callback);
  }

  setAttribute(name, value) {
    const stringValue = String(value);
    this.attributes.set(name, stringValue);
    if (name === "id") {
      this.id = stringValue;
    }
  }

  getAttribute(name) {
    if (name === "id") {
      return this.id || null;
    }
    return this.attributes.get(name) ?? null;
  }

  querySelectorAll(selector) {
    const matches = [];

    const visit = (node) => {
      if (!node || node.nodeType === "text") {
        return;
      }

      if (matchesSelector(node, selector)) {
        matches.push(node);
      }

      node.children.forEach((child) => visit(child));
    };

    this.children.forEach((child) => visit(child));
    return matches;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  closest(selector) {
    let current = this;
    while (current) {
      if (matchesSelector(current, selector)) {
        return current;
      }
      current = current.parentNode;
    }
    return null;
  }

  focus() {
    this.focused = true;
  }

  scrollIntoView() {
    this.scrolled = true;
  }
}

function installRendererDom() {
  const previousDocument = globalThis.document;
  const previousWindow = globalThis.window;

  globalThis.window = {
    setInterval() {
      return 1;
    },
    clearInterval() {},
  };

  globalThis.document = {
    createElement(tagName) {
      return new FakeElement(tagName);
    },
    createTextNode(text) {
      return { nodeType: "text", textContent: text, parentNode: null };
    },
    createDocumentFragment() {
      return new FakeFragment();
    },
  };

  return () => {
    globalThis.document = previousDocument;
    globalThis.window = previousWindow;
  };
}

function installAppDom() {
  const previousWindow = globalThis.window;
  const previousDocument = globalThis.document;
  const previousLocation = globalThis.location;

  const elements = {
    pageTitle: new FakeElement("h1"),
    pageSubtitle: new FakeElement("p"),
    dateTabs: new FakeElement("div"),
    searchInput: new FakeElement("input"),
    scopeSelect: new FakeElement("select"),
    statusMessage: new FakeElement("p"),
    timeslotAnnouncements: new FakeElement("p"),
    legend: new FakeElement("div"),
    clearFiltersButton: new FakeElement("button"),
    "rooms-container": new FakeElement("section"),
  };

  const documentListeners = new Map();
  let lastUrl = "/index.html";

  const windowObject = {
    location: {
      pathname: "/index.html",
      search: "",
    },
    localStorage: {
      values: new Map(),
      getItem(key) {
        return this.values.has(key) ? this.values.get(key) : null;
      },
      setItem(key, value) {
        this.values.set(key, value);
      },
    },
    history: {
      replaceState(_state, _title, url) {
        lastUrl = url;
        const parsed = new URL(url, "http://127.0.0.1:8000");
        windowObject.location.pathname = parsed.pathname;
        windowObject.location.search = parsed.search;
      },
    },
    setInterval() {
      return 1;
    },
    clearInterval() {},
  };

  globalThis.window = windowObject;
  globalThis.location = windowObject.location;
  globalThis.document = {
    title: "",
    createElement(tagName) {
      return new FakeElement(tagName);
    },
    createTextNode(text) {
      return { nodeType: "text", textContent: text, parentNode: null };
    },
    createDocumentFragment() {
      return new FakeFragment();
    },
    getElementById(id) {
      return elements[id] ?? null;
    },
    addEventListener(type, callback) {
      documentListeners.set(type, callback);
    },
  };

  return {
    elements,
    getLastUrl() {
      return lastUrl;
    },
    async dispatchDOMContentLoaded() {
      const callback = documentListeners.get("DOMContentLoaded");
      assert.equal(typeof callback, "function", "Expected app.js to register a DOMContentLoaded listener");
      callback();
      await waitFor(() => elements.legend.children.length > 0 && elements["rooms-container"].children.length > 0, 5000);
    },
    restore() {
      globalThis.window = previousWindow;
      globalThis.document = previousDocument;
      globalThis.location = previousLocation;
    },
  };
}

async function waitFor(predicate, timeoutMs) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  throw new Error(`Timed out after ${timeoutMs}ms waiting for condition`);
}

function createEvent(overrides = {}) {
  return {
    date: "2026-03-24",
    start: "09:00",
    end: "09:30",
    name: "Session",
    teams: [],
    vs: "ALL",
    topics: "Topic",
    location: "Room 1",
    type: "Breakout",
    ...overrides,
  };
}

function buildExpectedAnnouncement(events, selectedDate, now = new Date()) {
  if (events.length === 0) {
    return "No visible timeslots.";
  }

  const buckets = groupEventsByTimeslot(events);
  const bucketIndex = Math.max(findCurrentBucketIndex(buckets, selectedDate, now), 0);
  const bucket = buckets[bucketIndex] ?? buckets[0];

  if (!bucket) {
    return "No visible timeslots.";
  }

  const itemCount = bucket.events.length;
  return `Showing events from ${bucket.bucketLabel}, ${itemCount} ${itemCount === 1 ? "item" : "items"}`;
}

function findDateWithAtLeastBucketCount(events, minimumBuckets) {
  const uniqueDates = [...new Set(events.map((event) => event.date).filter(Boolean))];

  for (const date of uniqueDates) {
    const dayEvents = filterEvents(events, {
      date,
      mode: "all",
      value: "",
      search: "",
    });
    const buckets = groupEventsByTimeslot(dayEvents);
    if (buckets.length >= minimumBuckets) {
      return { date, buckets };
    }
  }

  return null;
}

function assertAllRenderedTimeslotsExpanded(container) {
  const groups = container.querySelectorAll(".timeslot-group");
  assert.ok(groups.length > 0, "Expected at least one rendered timeslot group");

  groups.forEach((group, index) => {
    const toggle = group.querySelector(".timeslot-toggle");
    const cards = group.querySelector(".timeslot-cards");

    assert.notEqual(toggle, null, `Expected timeslot ${index + 1} to include a toggle`);
    assert.notEqual(cards, null, `Expected timeslot ${index + 1} to include a cards wrapper`);
    assert.equal(toggle.getAttribute("aria-expanded"), "true", `Expected timeslot ${index + 1} to start expanded`);
    assert.equal(cards.hidden, false, `Expected timeslot ${index + 1} cards to be visible`);
    assert.equal(group.classList.contains("timeslot-collapsed"), false, `Expected timeslot ${index + 1} not to be marked collapsed`);
  });

  return groups;
}

function clickDateTab(dom, targetDate) {
  const dateButton = dom.elements.dateTabs.children.find((child) => child?.dataset?.date === targetDate);
  assert.notEqual(dateButton, undefined, `Expected a rendered date tab for ${targetDate}`);
  dom.elements.dateTabs.listeners.get("click")({ target: dateButton });
}

await runTest("renderTimeslotGroups exposes accessible headings and toggle control relationships", async () => {
  const restoreDom = installRendererDom();

  try {
    const container = new FakeElement("section");
    container.className = "rooms";
    const colorMap = {
      ALL: { bg: "#fff", border: "#000" },
      _default: { bg: "#fff", border: "#999" },
    };
    const buckets = [
      {
        bucketKey: "09:00",
        bucketLabel: "09:00 – 09:30",
        events: [createEvent({ start: "09:00", name: "A" }), createEvent({ start: "09:15", name: "B" })],
      },
    ];

    const groups = renderTimeslotGroups(container, buckets, colorMap, {
      expandedCount: 4,
      currentBucketIndex: 0,
    });

    assert.equal(groups.length, 1);
    assert.equal(groups[0].tagName, "DIV", "timeslot groups should be non-landmark wrappers rather than unnamed sections");

    const header = groups[0].querySelector(".timeslot-header");
    const toggle = groups[0].querySelector(".timeslot-toggle");
    const cards = groups[0].querySelector(".timeslot-cards");

    assert.equal(header?.getAttribute("role"), "heading");
    assert.equal(header?.getAttribute("aria-level"), "3");
    assert.equal(header?.tabIndex, -1);
    assert.equal(toggle?.type, "button");
    assert.equal(toggle?.getAttribute("aria-expanded"), "true");
    assert.equal(toggle?.getAttribute("aria-controls"), cards?.id);
    assert.equal(toggle?.getAttribute("aria-label"), "Collapse 09:00 – 09:30");
    assert.equal(cards?.hidden, false);
  } finally {
    restoreDom();
  }
});

await runTest("app updates the dedicated timeslot live region when filters change the visible groups", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    await import(new URL(`../app.js?timeslot-review-followups=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    const selectedDate = currentUrl.searchParams.get("date");
    assert.notEqual(selectedDate, null, "Expected the app to persist a selected date in URL state");

    const initialEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: "",
    });
    const initialAnnouncement = buildExpectedAnnouncement(initialEvents, selectedDate);
    assert.equal(dom.elements.timeslotAnnouncements.textContent, initialAnnouncement);

    const searchableToken = [...new Set(initialEvents.map((event) => event.vs).filter((value) => value && value !== "ALL"))]
      .find((token) => {
        const filteredEvents = filterEvents(loaded.events, {
          date: selectedDate,
          mode: "all",
          value: "",
          search: token,
        });
        return filteredEvents.length > 0 && buildExpectedAnnouncement(filteredEvents, selectedDate) !== initialAnnouncement;
      });

    assert.notEqual(searchableToken, undefined, "Expected at least one non-ALL value stream to produce a different live-region summary");

    dom.elements.searchInput.value = searchableToken;
    dom.elements.searchInput.listeners.get("input")();

    const filteredEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: searchableToken,
    });
    const filteredAnnouncement = buildExpectedAnnouncement(filteredEvents, selectedDate);

    assert.equal(dom.elements.timeslotAnnouncements.textContent, filteredAnnouncement);
    assert.notEqual(filteredAnnouncement, initialAnnouncement, "Expected the live-region summary to change after filtering");
  } finally {
    dom.restore();
  }
});

await runTest("app renders all visible timeslots expanded for a day with more than four buckets", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    const targetDay = findDateWithAtLeastBucketCount(loaded.events, 5);
    assert.notEqual(targetDay, null, "Expected committed schedule data to contain at least one day with five or more timeslot buckets");

    await import(new URL(`../app.js?expand-all-timeslots-initial=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    if (currentUrl.searchParams.get("date") !== targetDay.date) {
      clickDateTab(dom, targetDay.date);
    }

    const groups = assertAllRenderedTimeslotsExpanded(dom.elements["rooms-container"]);
    assert.equal(groups.length, targetDay.buckets.length, "Expected every bucket for the selected day to be rendered and expanded");
    assert.ok(groups.length >= 5, "Expected this regression test to exercise more than four timeslots");
  } finally {
    dom.restore();
  }
});

await runTest("clearing filters restores the full day with every visible timeslot expanded", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    const targetDay = findDateWithAtLeastBucketCount(loaded.events, 5);
    assert.notEqual(targetDay, null, "Expected committed schedule data to contain at least one day with five or more timeslot buckets");

    const searchableToken = [...new Set(targetDay.buckets.flatMap((bucket) => bucket.events.map((event) => event.vs)).filter((value) => value && value !== "ALL"))][0];
    assert.notEqual(searchableToken, undefined, "Expected the chosen day to contain at least one searchable non-ALL value stream");

    await import(new URL(`../app.js?expand-all-timeslots-clear=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    if (currentUrl.searchParams.get("date") !== targetDay.date) {
      clickDateTab(dom, targetDay.date);
    }

    dom.elements.searchInput.value = searchableToken;
    dom.elements.searchInput.listeners.get("input")();
    assert.equal(dom.elements.clearFiltersButton.hidden, false, "Expected the clear button to appear after applying a search filter");

    dom.elements.clearFiltersButton.listeners.get("click")();

    const groups = assertAllRenderedTimeslotsExpanded(dom.elements["rooms-container"]);
    assert.equal(groups.length, targetDay.buckets.length, "Expected clearing filters to restore every bucket for the selected day");
    assert.equal(dom.elements.clearFiltersButton.hidden, true, "Expected the clear button to hide again after clearing filters");
  } finally {
    dom.restore();
  }
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

