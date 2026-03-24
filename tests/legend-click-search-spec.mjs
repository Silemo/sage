import assert from "node:assert/strict";

import { loadAllSources } from "../js/loader.js";
import { filterEvents } from "../js/filter.js";
import { renderLegend } from "../js/renderer.js";

const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const nativeFetch = globalThis.fetch;

if (typeof nativeFetch !== "function") {
  throw new Error("Global fetch is required to run legend-click-search-spec.mjs");
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

function installMinimalDom() {
  const previousDocument = globalThis.document;

  globalThis.document = {
    createElement(tagName) {
      return new FakeElement(tagName);
    },
    createTextNode(text) {
      return { nodeType: "text", textContent: text, parentNode: null };
    },
  };

  return () => {
    globalThis.document = previousDocument;
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
    legend: new FakeElement("div"),
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

await runTest("legend renderer exposes one item per value stream for delegated clicks", async () => {
  const restoreDom = installMinimalDom();

  try {
    const container = new FakeElement("div");
    const colorMap = {
      ALL: { bg: "#ccc", border: "#111" },
      MON: { bg: "#fed", border: "#321" },
      _default: { bg: "#fff", border: "#999" },
    };

    renderLegend(container, colorMap, [
      { name: "Overall PI Plenary", vs: "ALL" },
      { name: "Coffee break", vs: "ALL" },
      { name: "VS MON Plenary", vs: "MON" },
      { name: "Misconfigured", vs: "" },
    ]);

    assert.deepEqual(
      container.children.map((item) => item.children[1]?.textContent),
      ["ALL", "MON"],
    );
    assert.deepEqual(
      container.children.map((item) => item.dataset.vs),
      ["ALL", "MON"],
    );
  } finally {
    restoreDom();
  }
});

await runTest("clicking a legend child updates search input, URL, and filtered cards for the selected value stream", async () => {
  const dom = installAppDom();

  try {
    const sources = await fetchJson("config/sources.json");
    const loaded = await loadAllSources(sources);
    assert.equal(loaded.errors.length, 0, "Committed sources should load without warnings for this interaction test");

    const selectedDate = sources.sources[0].defaultDate;
    const targetValueStream = "MON";
    const expectedFiltered = filterEvents(loaded.events, {
      date: selectedDate,
      mode: "all",
      value: "",
      search: targetValueStream,
    });

    await import(new URL(`../app.js?legend-click-search=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const initialUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(initialUrl.searchParams.get("search"), null);

    const targetItem = findLegendItem(dom.elements.legend, targetValueStream);
    assert.notEqual(targetItem, null, `Expected the rendered legend to include ${targetValueStream}`);

    const label = targetItem.children[1];
    dom.elements.legend.listeners.get("click")({ target: label });

    const updatedUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, targetValueStream);
    assert.equal(updatedUrl.searchParams.get("search"), targetValueStream);
    assert.equal(updatedUrl.searchParams.get("date"), selectedDate);
    assert.equal(
      dom.elements["rooms-container"].querySelectorAll(".room-card").length,
      expectedFiltered.length,
    );
  } finally {
    dom.restore();
  }
});

await runTest("legend container gap clicks do not change the active search before a swatch click selects a value stream", async () => {
  const dom = installAppDom();

  try {
    await import(new URL(`../app.js?legend-click-search-gap=${Date.now()}`, import.meta.url));
    await dom.dispatchDOMContentLoaded();

    const clickHandler = dom.elements.legend.listeners.get("click");
    assert.equal(typeof clickHandler, "function", "Expected the legend container to register a click handler");

    clickHandler({ target: dom.elements.legend });

    let currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, "");
    assert.equal(currentUrl.searchParams.get("search"), null);

    const targetItem = dom.elements.legend.children.find((child) => child?.dataset?.vs && child.dataset.vs !== "ALL");
    assert.notEqual(targetItem, null, "Expected at least one value-stream-specific legend item");

    const swatch = targetItem.children[0];
    clickHandler({ target: swatch });

    currentUrl = new URL(dom.getLastUrl(), "http://127.0.0.1:8000");
    assert.equal(dom.elements.searchInput.value, targetItem.dataset.vs);
    assert.equal(currentUrl.searchParams.get("search"), targetItem.dataset.vs);
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