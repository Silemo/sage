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
