import assert from "node:assert/strict";

import {
  findCurrentBucketIndex,
  formatBucketLabel,
  getBucketKey,
  groupEventsByTimeslot,
} from "../js/timeslot.js";
import { renderTimeslotGroups } from "../js/renderer.js";
import { applyTimeslotIndicator } from "../js/time-indicator.js";

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

function createStyle() {
  return {
    values: {},
    setProperty(name, value) {
      this.values[name] = value;
    },
  };
}

class FakeNode {
  constructor() {
    this.parentNode = null;
  }
}

class FakeFragment extends FakeNode {
  constructor() {
    super();
    this.children = [];
  }

  appendChild(node) {
    if (node && typeof node === "object") {
      node.parentNode = this;
    }
    this.children.push(node);
    return node;
  }
}

function getClassNames(element) {
  return String(element.className ?? "").split(/\s+/).filter(Boolean);
}

function matchesSelector(element, selector) {
  if (!element || element.nodeType === "text") {
    return false;
  }

  const classNames = getClassNames(element);
  const hasClass = (className) => classNames.includes(className);

  switch (selector) {
    case ".timeslot-group":
      return hasClass("timeslot-group");
    case ".timeslot-header":
      return hasClass("timeslot-header");
    case ".timeslot-toggle":
      return hasClass("timeslot-toggle");
    case ".timeslot-now":
      return hasClass("timeslot-now");
    case ".timeslot-cards":
      return hasClass("timeslot-cards");
    case ".timeslot-label":
      return hasClass("timeslot-label");
    case ".room-card":
      return hasClass("room-card");
    default:
      return false;
  }
}

class FakeElement extends FakeNode {
  constructor(tagName) {
    super();
    this.tagName = String(tagName).toUpperCase();
    this.className = "";
    this.textContent = "";
    this.children = [];
    this.dataset = {};
    this.attributes = new Map();
    this.style = createStyle();
    this.hidden = false;
    this.id = "";
    this.tabIndex = 0;
    this.focused = false;
    this.scrolled = false;
    this.classList = {
      add: (...tokens) => {
        const values = new Set(getClassNames(this));
        tokens.forEach((token) => values.add(token));
        this.className = [...values].join(" ");
      },
      remove: (...tokens) => {
        const values = getClassNames(this).filter((token) => !tokens.includes(token));
        this.className = values.join(" ");
      },
      toggle: (token, force) => {
        const values = new Set(getClassNames(this));
        const shouldAdd = force === undefined ? !values.has(token) : Boolean(force);
        if (shouldAdd) {
          values.add(token);
        } else {
          values.delete(token);
        }
        this.className = [...values].join(" ");
        return shouldAdd;
      },
      contains: (token) => getClassNames(this).includes(token),
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

  setAttribute(name, value) {
    const stringValue = String(value);
    this.attributes.set(name, stringValue);
    if (name === "id") {
      this.id = stringValue;
    }
  }

  getAttribute(name) {
    if (name === "id" && this.id) {
      return this.id;
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

function installDom() {
  const previousDocument = globalThis.document;
  const previousWindow = globalThis.window;

  globalThis.window = {
    setInterval(callback) {
      callback();
      return 1;
    },
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

await runTest("getBucketKey rounds times to 30-minute boundaries", async () => {
  assert.equal(getBucketKey("09:00"), "09:00");
  assert.equal(getBucketKey("09:15"), "09:00");
  assert.equal(getBucketKey("09:30"), "09:30");
  assert.equal(getBucketKey("23:45"), "23:30");
});

await runTest("formatBucketLabel formats bucket ranges including midnight wrap", async () => {
  assert.equal(formatBucketLabel("09:00"), "09:00 – 09:30");
  assert.equal(formatBucketLabel("23:30"), "23:30 – 00:00");
});

await runTest("groupEventsByTimeslot groups mixed event times and preserves sorted order", async () => {
  const grouped = groupEventsByTimeslot([
    createEvent({ start: "09:35", end: "10:00", name: "C" }),
    createEvent({ start: "09:05", end: "09:20", name: "B" }),
    createEvent({ start: "09:00", end: "09:15", name: "A" }),
    createEvent({ start: "10:00", end: "10:30", name: "D" }),
  ]);

  assert.deepEqual(
    grouped.map((bucket) => bucket.bucketKey),
    ["09:00", "09:30", "10:00"],
  );
  assert.deepEqual(
    grouped[0].events.map((event) => event.name),
    ["A", "B"],
  );
  assert.equal(groupEventsByTimeslot([]).length, 0);
});

await runTest("findCurrentBucketIndex returns expected bucket positions for today and non-today", async () => {
  const buckets = groupEventsByTimeslot([
    createEvent({ start: "09:00" }),
    createEvent({ start: "09:30" }),
    createEvent({ start: "10:00" }),
  ]);

  assert.equal(
    findCurrentBucketIndex(buckets, "2026-03-24", new Date("2026-03-24T09:10:00")),
    0,
  );
  assert.equal(
    findCurrentBucketIndex(buckets, "2026-03-24", new Date("2026-03-24T09:45:00")),
    1,
  );
  assert.equal(
    findCurrentBucketIndex(buckets, "2026-03-23", new Date("2026-03-24T09:10:00")),
    -1,
  );
  assert.equal(
    findCurrentBucketIndex(buckets, "2026-03-24", new Date("2026-03-24T23:45:00")),
    -1,
  );
});

await runTest("renderTimeslotGroups creates grouped containers, nested cards, and collapsed state", async () => {
  const restoreDom = installDom();

  try {
    const container = new FakeElement("section");
    container.className = "rooms";
    const colorMap = {
      ALL: { bg: "#fff", border: "#000" },
      _default: { bg: "#fff", border: "#999" },
    };
    const buckets = groupEventsByTimeslot([
      createEvent({ start: "09:00", name: "A" }),
      createEvent({ start: "09:10", name: "B" }),
      createEvent({ start: "09:30", name: "C" }),
    ]);

    const groups = renderTimeslotGroups(container, buckets, colorMap, {
      expandedCount: 1,
      currentBucketIndex: 1,
    });

    assert.equal(groups.length, 2);
    assert.equal(container.classList.contains("timeslot-layout"), true);
    assert.equal(container.querySelectorAll(".timeslot-group").length, 2);
    assert.equal(container.querySelectorAll(".room-card").length, 3);
    assert.equal(container.querySelectorAll(".timeslot-now").length, 1);
    assert.equal(groups[0].querySelector(".timeslot-toggle").getAttribute("aria-expanded"), "false");
    assert.equal(groups[0].querySelector(".timeslot-cards").hidden, true);
    assert.equal(groups[1].querySelector(".timeslot-toggle").getAttribute("aria-expanded"), "true");
    assert.equal(groups[1].querySelector(".timeslot-cards").hidden, false);
  } finally {
    restoreDom();
  }
});

await runTest("applyTimeslotIndicator moves the current highlight between rendered groups", async () => {
  const restoreDom = installDom();

  try {
    const container = new FakeElement("section");
    container.className = "rooms";
    const colorMap = {
      ALL: { bg: "#fff", border: "#000" },
      _default: { bg: "#fff", border: "#999" },
    };
    const buckets = groupEventsByTimeslot([
      createEvent({ start: "09:00", name: "A" }),
      createEvent({ start: "09:30", name: "B" }),
    ]);

    renderTimeslotGroups(container, buckets, colorMap, {
      expandedCount: 2,
      currentBucketIndex: -1,
    });

    applyTimeslotIndicator(container, 0);
    assert.equal(container.querySelectorAll(".timeslot-now").length, 1);
    assert.equal(container.querySelectorAll(".timeslot-group")[0].classList.contains("timeslot-now"), true);

    applyTimeslotIndicator(container, 1);
    assert.equal(container.querySelectorAll(".timeslot-now").length, 1);
    assert.equal(container.querySelectorAll(".timeslot-group")[0].classList.contains("timeslot-now"), false);
    assert.equal(container.querySelectorAll(".timeslot-group")[1].classList.contains("timeslot-now"), true);
  } finally {
    restoreDom();
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

