import assert from "node:assert/strict";

import { loadAllSources } from "../js/loader.js";
import { filterEvents } from "../js/filter.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run clear-filter-button-spec.mjs");
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

function matchesSelector(element, selector) {
  if (!element || element.nodeType === "text") {
    return false;
  }

  const classNames = String(element.className ?? "").split(/\s+/).filter(Boolean);
  const hasClass = (className) => classNames.includes(className);

  if (selector === ".time-indicator") {
    return hasClass("time-indicator");
  }

  if (selector === ".room-card") {
    return hasClass("room-card");
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
    this.classList = {
      add: (...tokens) => {
        const values = new Set(String(this.className).split(/\s+/).filter(Boolean));
        tokens.forEach((token) => values.add(token));
        this.className = [...values].join(" ");
      },
    };
  }

  append(...nodes) {
    nodes.forEach((node) => this.appendChild(node));
  }

  appendChild(node) {
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

  remove() {
    if (!this.parentNode) {
      return;
    }

    const index = this.parentNode.children.indexOf(this);
    if (index >= 0) {
      this.parentNode.children.splice(index, 1);
    }
    this.parentNode = null;
  }
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

function findLegendItem(container, valueStream) {
  return container.children.find((child) => child?.dataset?.vs === valueStream) ?? null;
}

await runTest("clear button stays hidden on initial load with default filters", async () => {
  const dom = installAppDom();

  try {
    await import(new URL(`../app.js?clear-filter-default=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    assert.equal(dom.elements.clearFiltersButton.hidden, true);

    const currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(currentUrl.searchParams.get("mode"), null);
    assert.equal(currentUrl.searchParams.get("value"), null);
    assert.equal(currentUrl.searchParams.get("search"), null);
  } finally {
    dom.restore();
  }
});

await runTest("typing a search shows the clear button and clearing preserves the selected day", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    await import(new URL(`../app.js?clear-filter-search=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const dateClickHandler = dom.elements.dateTabs.listeners.get("click");
    const availableDateButtons = dom.elements.dateTabs.children.filter((child) => child?.dataset?.date);
    const selectedDateButton = availableDateButtons[1] ?? availableDateButtons[0];
    assert.notEqual(selectedDateButton, undefined, "Expected at least one date tab to be rendered");
    dateClickHandler({ target: selectedDateButton });

    const selectedDate = selectedDateButton.dataset.date;
    const filteredEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: "MON",
    });
    const clearedEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: "",
    });

    dom.elements.searchInput.value = "MON";
    dom.elements.searchInput.listeners.get("input")();

    let currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.clearFiltersButton.hidden, false);
    assert.equal(currentUrl.searchParams.get("search"), "MON");
    assert.equal(currentUrl.searchParams.get("date"), selectedDate);
    assert.equal(dom.elements["rooms-container"].querySelectorAll(".room-card").length, filteredEvents.length);

    dom.elements.clearFiltersButton.listeners.get("click")();

    currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, "");
    assert.equal(dom.elements.scopeSelect.value, "all");
    assert.equal(dom.elements.clearFiltersButton.hidden, true);
    assert.equal(currentUrl.searchParams.get("search"), null);
    assert.equal(currentUrl.searchParams.get("mode"), null);
    assert.equal(currentUrl.searchParams.get("value"), null);
    assert.equal(currentUrl.searchParams.get("date"), selectedDate);
    assert.equal(dom.elements["rooms-container"].querySelectorAll(".room-card").length, clearedEvents.length);
    assert.ok(dom.elements.legend.children.length > 0, "Expected the legend to be rendered after clearing filters");
  } finally {
    dom.restore();
  }
});

await runTest("scope-only filtering shows the clear button and clearing restores all activities without changing search", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    await import(new URL(`../app.js?clear-filter-scope=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const dateUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    const selectedDate = dateUrl.searchParams.get("date");
    assert.notEqual(selectedDate, null, "Expected initial state to include a selected date");

    const targetOption = dom.elements.scopeSelect.children
      .flatMap((child) => child.tagName === "OPTGROUP" ? child.children : [child])
      .find((child) => child?.value?.startsWith("vs:"));
    assert.notEqual(targetOption, undefined, "Expected at least one value stream scope option");

    dom.elements.scopeSelect.value = targetOption.value;
    dom.elements.scopeSelect.listeners.get("change")();

    let currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    const [, selectedValueStream] = targetOption.value.split(":");
    const filteredEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "vs",
      value: selectedValueStream,
      search: "",
    });
    const clearedEvents = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: "",
    });

    assert.equal(dom.elements.searchInput.value, "");
    assert.equal(dom.elements.clearFiltersButton.hidden, false);
    assert.equal(currentUrl.searchParams.get("mode"), "vs");
    assert.equal(currentUrl.searchParams.get("value"), selectedValueStream);
    assert.equal(currentUrl.searchParams.get("search"), null);
    assert.equal(dom.elements["rooms-container"].querySelectorAll(".room-card").length, filteredEvents.length);

    dom.elements.clearFiltersButton.listeners.get("click")();

    currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, "");
    assert.equal(dom.elements.scopeSelect.value, "all");
    assert.equal(dom.elements.clearFiltersButton.hidden, true);
    assert.equal(currentUrl.searchParams.get("mode"), null);
    assert.equal(currentUrl.searchParams.get("value"), null);
    assert.equal(currentUrl.searchParams.get("search"), null);
    assert.equal(currentUrl.searchParams.get("date"), selectedDate);
    assert.equal(dom.elements["rooms-container"].querySelectorAll(".room-card").length, clearedEvents.length);
  } finally {
    dom.restore();
  }
});

await runTest("legend clicks activate the clear button because they create a search filter", async () => {
  const dom = installAppDom();

  try {
    await import(new URL(`../app.js?clear-filter-legend=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const targetItem = dom.elements.legend.children.find((child) => child?.dataset?.vs && child.dataset.vs !== "ALL");
    assert.notEqual(targetItem, null, "Expected at least one value-stream-specific legend item");

    const label = targetItem.children[1] ?? targetItem;
    dom.elements.legend.listeners.get("click")({ target: label });

    const currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, targetItem.dataset.vs);
    assert.equal(dom.elements.clearFiltersButton.hidden, false);
    assert.equal(currentUrl.searchParams.get("search"), targetItem.dataset.vs);

    const legendEntry = findLegendItem(dom.elements.legend, targetItem.dataset.vs);
    assert.notEqual(legendEntry, null, "Expected the filtered legend to still contain the searched value stream");
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