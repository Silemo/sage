export function clearContainer(container) {
  container.replaceChildren();
}

export function getEventColor(event, colorMap) {
  return colorMap[event.vs] ?? colorMap._default;
}

function createDetailRow(label, value, className) {
  const row = document.createElement("p");
  row.className = className;

  const strong = document.createElement("strong");
  strong.textContent = `${label}: `;

  const text = document.createTextNode(value);
  row.append(strong, text);
  return row;
}

export function createRoomCard(event, colorMap) {
  const card = document.createElement("article");
  const color = getEventColor(event, colorMap);
  card.className = "room-card";
  card.style.setProperty("--card-bg", color.bg);
  card.style.setProperty("--card-border", color.border);

  const time = document.createElement("div");
  time.className = "card-time";
  time.textContent = `${event.start} - ${event.end}`;

  const team = document.createElement("h2");
  team.className = "card-team";
  team.textContent = event.name;

  const location = createDetailRow("Location", event.location, "card-location");
  const topics = createDetailRow("Topics", event.topics, "card-topics");
  const valueStream = createDetailRow("Value Stream", event.vs || "All", "card-vs");

  const type = document.createElement("span");
  type.className = "card-type";
  type.textContent = event.type;

  card.append(time, team, location, topics, valueStream, type);
  return card;
}

export function renderEmptyState(container, message) {
  const state = document.createElement("p");
  state.className = "empty-state";
  state.textContent = message;
  container.appendChild(state);
}

export function renderErrorState(container, message) {
  const state = document.createElement("p");
  state.className = "error-state";
  state.textContent = message;
  container.appendChild(state);
}

function createTimeslotToggle(bucketLabel, controlsId, isExpanded) {
  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.className = "timeslot-toggle";
  toggle.textContent = isExpanded ? "▾" : "▸";
  toggle.setAttribute("aria-expanded", String(isExpanded));
  toggle.setAttribute("aria-controls", controlsId);
  toggle.setAttribute("aria-label", `${isExpanded ? "Collapse" : "Expand"} ${bucketLabel}`);
  return toggle;
}

function createTimeslotHeader(bucket, cardsId, isExpanded) {
  const header = document.createElement("div");
  header.className = "timeslot-header";
  header.setAttribute("role", "heading");
  header.setAttribute("aria-level", "3");
  header.tabIndex = -1;

  const label = document.createElement("span");
  label.className = "timeslot-label";
  label.textContent = bucket.bucketLabel;

  const count = document.createElement("span");
  count.className = "timeslot-count";
  count.textContent = `${bucket.events.length} event${bucket.events.length === 1 ? "" : "s"}`;

  const toggle = createTimeslotToggle(bucket.bucketLabel, cardsId, isExpanded);
  header.append(label, count, toggle);
  return header;
}

function isInitiallyExpanded(index, currentBucketIndex, expandedCount) {
  if (currentBucketIndex >= 0) {
    return index >= currentBucketIndex && index < currentBucketIndex + expandedCount;
  }

  return index < expandedCount;
}

function createTimeslotGroup(bucket, colorMap, options) {
  const { index, currentBucketIndex, expandedCount } = options;
  const isCurrent = index === currentBucketIndex;
  const isExpanded = isInitiallyExpanded(index, currentBucketIndex, expandedCount);
  const cardsId = `timeslot-cards-${bucket.bucketKey.replace(/[^a-z0-9]+/gi, "-")}-${index}`;

  const group = document.createElement("div");
  group.className = "timeslot-group";
  group.dataset.bucket = bucket.bucketKey;
  if (isCurrent) {
    group.classList.add("timeslot-now");
  }
  if (!isExpanded) {
    group.classList.add("timeslot-collapsed");
  }

  const header = createTimeslotHeader(bucket, cardsId, isExpanded);

  const cards = document.createElement("div");
  cards.className = "timeslot-cards";
  cards.id = cardsId;
  cards.hidden = !isExpanded;

  bucket.events.forEach((event) => {
    cards.appendChild(createRoomCard(event, colorMap));
  });

  group.append(header, cards);
  return group;
}

export function renderTimeslotGroups(container, buckets, colorMap, options = {}) {
  clearContainer(container);
  container.classList.add("timeslot-layout");

  if (buckets.length === 0) {
    renderEmptyState(container, "No activities match the current filters.");
    return [];
  }

  const fragment = document.createDocumentFragment();
  const groups = buckets.map((bucket, index) => createTimeslotGroup(bucket, colorMap, {
    index,
    currentBucketIndex: options.currentBucketIndex ?? -1,
    expandedCount: options.expandedCount ?? 4,
  }));

  groups.forEach((group) => fragment.appendChild(group));
  container.appendChild(fragment);
  return groups;
}

export function renderCards(container, events, colorMap) {
  clearContainer(container);

  if (events.length === 0) {
    renderEmptyState(container, "No activities match the current filters.");
    return [];
  }

  const cards = events.map((event) => createRoomCard(event, colorMap));
  cards.forEach((card) => container.appendChild(card));
  return cards;
}

export function renderLegend(container, colorMap, events) {
  clearContainer(container);
  const activeStreams = [...new Set(events
    .map((event) => event.vs)
    .filter(Boolean))];

  if (activeStreams.length === 0) {
    return;
  }

  activeStreams.sort((left, right) => left.localeCompare(right)).forEach((valueStream) => {
    const item = document.createElement("div");
    item.className = "legend-item";
    item.dataset.vs = valueStream;

    const swatch = document.createElement("span");
    swatch.className = "legend-swatch";
    const color = colorMap[valueStream] ?? colorMap._default;
    swatch.style.setProperty("--legend-bg", color.bg);
    swatch.style.setProperty("--legend-border", color.border);

    const label = document.createElement("span");
    label.className = "legend-label";
    label.textContent = valueStream;

    item.append(swatch, label);
    container.appendChild(item);
  });
}
