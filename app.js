import { loadAllSources } from "./js/loader.js";
import { buildHierarchy, filterEvents } from "./js/filter.js";
import { readState, writeState } from "./js/url-state.js";
import { renderCards, renderErrorState, renderLegend } from "./js/renderer.js";
import { clearIndicator, insertIndicator, startIndicatorUpdates } from "./js/time-indicator.js";

const appState = {
  allEvents: [],
  colors: {},
  hierarchy: {
    dates: [],
    valueStreams: {},
  },
  filterState: {
    date: "",
    mode: "all",
    value: "",
    search: "",
  },
  indicatorTimer: null,
};

function getElements() {
  return {
    title: document.getElementById("pageTitle"),
    subtitle: document.getElementById("pageSubtitle"),
    dateTabs: document.getElementById("dateTabs"),
    searchInput: document.getElementById("searchInput"),
    scopeSelect: document.getElementById("scopeSelect"),
    statusMessage: document.getElementById("statusMessage"),
    legend: document.getElementById("legend"),
    clearFiltersButton: document.getElementById("clearFiltersButton"),
    rooms: document.getElementById("rooms-container"),
  };
}

async function fetchJson(path) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`Failed to load ${path}: ${response.status}`);
  }
  return response.json();
}

function getScopeSelectValue(state) {
  if (state.mode === "vs") {
    return `vs:${state.value}`;
  }
  if (state.mode === "team") {
    return `team:${state.value}`;
  }
  return state.mode;
}

function setStatusMessage(message, tone = "info") {
  const { statusMessage } = getElements();
  statusMessage.textContent = message;
  statusMessage.dataset.tone = tone;
  statusMessage.hidden = message === "";
}

function updateTitle() {
  const { title, subtitle } = getElements();
  const matchingDayIndex = appState.hierarchy.dates.indexOf(appState.filterState.date);
  const dayLabel = matchingDayIndex >= 0 ? `Day ${matchingDayIndex + 1}` : "Schedule";
  title.textContent = `SAGE - ${dayLabel}`;
  subtitle.textContent = appState.filterState.mode === "all"
    ? "All activities"
    : `Filtered view: ${getScopeSelectValue(appState.filterState).replace(":", " - ")}`;
  document.title = title.textContent;
}

function buildDateTabs(dates, selectedDate) {
  const { dateTabs } = getElements();
  dateTabs.replaceChildren();

  dates.forEach((date, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "date-tab";
    if (date === selectedDate) {
      button.classList.add("active");
    }
    button.dataset.date = date;
    const formatted = new Date(`${date}T00:00:00`).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
    });
    button.textContent = `Day ${index + 1} - ${formatted}`;
    dateTabs.appendChild(button);
  });
}

function buildScopeSelect(hierarchy, state) {
  const { scopeSelect } = getElements();
  scopeSelect.replaceChildren();

  const allOption = document.createElement("option");
  allOption.value = "all";
  allOption.textContent = "All activities";
  scopeSelect.appendChild(allOption);

  const plenaryOption = document.createElement("option");
  plenaryOption.value = "plenary";
  plenaryOption.textContent = "Plenary";
  scopeSelect.appendChild(plenaryOption);

  Object.entries(hierarchy.valueStreams).forEach(([valueStream, teams]) => {
    const group = document.createElement("optgroup");
    group.label = valueStream;

    const valueStreamOption = document.createElement("option");
    valueStreamOption.value = `vs:${valueStream}`;
    valueStreamOption.textContent = `All ${valueStream}`;
    group.appendChild(valueStreamOption);

    teams.forEach((team) => {
      const teamOption = document.createElement("option");
      teamOption.value = `team:${team}`;
      teamOption.textContent = team;
      group.appendChild(teamOption);
    });

    scopeSelect.appendChild(group);
  });

  const requestedValue = getScopeSelectValue(state);
  scopeSelect.value = requestedValue;

  if (scopeSelect.value !== requestedValue) {
    scopeSelect.value = "all";
    appState.filterState.mode = "all";
    appState.filterState.value = "";
  }
}

function buildControls(hierarchy, state) {
  const { searchInput } = getElements();
  buildDateTabs(hierarchy.dates, state.date);
  buildScopeSelect(hierarchy, state);
  searchInput.value = state.search;
  updateTitle();
}

function getSelectedEvents() {
  return filterEvents(appState.allEvents, appState.filterState);
}

function isFilterActive(filterState) {
  return filterState.mode !== "all" || filterState.search !== "";
}

function updateClearButton() {
  const { clearFiltersButton } = getElements();
  if (clearFiltersButton) {
    clearFiltersButton.hidden = !isFilterActive(appState.filterState);
  }
}

function clearFilters() {
  const { searchInput, scopeSelect } = getElements();
  appState.filterState.mode = "all";
  appState.filterState.value = "";
  appState.filterState.search = "";
  if (searchInput) {
    searchInput.value = "";
  }
  if (scopeSelect) {
    scopeSelect.value = "all";
  }
  applyCurrentFilters();
}

function updateView() {
  const elements = getElements();
  const selectedEvents = getSelectedEvents();
  renderCards(elements.rooms, selectedEvents, appState.colors);
  renderLegend(elements.legend, appState.colors, selectedEvents);
  updateClearButton();
  insertIndicator(elements.rooms, selectedEvents, appState.filterState.date);
  writeState(appState.filterState);
  updateTitle();
}

function applyCurrentFilters() {
  updateView();
}

function parseScopeValue(rawValue) {
  if (rawValue === "all" || rawValue === "plenary") {
    return { mode: rawValue, value: "" };
  }

  const [mode, value] = rawValue.split(":");
  return { mode, value: value ?? "" };
}

async function initializeApp() {
  const [sourcesConfig, colors] = await Promise.all([
    fetchJson("./config/sources.json"),
    fetchJson("./config/colors.json"),
  ]);

  const { events, errors } = await loadAllSources(sourcesConfig);
  appState.allEvents = events;
  appState.colors = colors;
  appState.hierarchy = buildHierarchy(events);
  appState.filterState = readState(appState.hierarchy.dates);

  buildControls(appState.hierarchy, appState.filterState);
  applyCurrentFilters();

  const { dateTabs, searchInput, scopeSelect, legend, clearFiltersButton, rooms } = getElements();

  if (clearFiltersButton) {
    clearFiltersButton.addEventListener("click", clearFilters);
  }

  dateTabs.addEventListener("click", (clickEvent) => {
    const button = clickEvent.target.closest("button[data-date]");
    if (!button) {
      return;
    }

    appState.filterState.date = button.dataset.date ?? appState.filterState.date;
    buildDateTabs(appState.hierarchy.dates, appState.filterState.date);
    applyCurrentFilters();
  });

  legend.addEventListener("click", (clickEvent) => {
    const item = clickEvent.target.closest(".legend-item[data-vs]");
    if (!item) {
      return;
    }

    appState.filterState.search = item.dataset.vs;
    searchInput.value = appState.filterState.search;
    applyCurrentFilters();
  });

  searchInput.addEventListener("input", () => {
    appState.filterState.search = searchInput.value;
    applyCurrentFilters();
  });

  scopeSelect.addEventListener("change", () => {
    const scope = parseScopeValue(scopeSelect.value);
    appState.filterState.mode = scope.mode;
    appState.filterState.value = scope.value;
    applyCurrentFilters();
  });

  if (appState.indicatorTimer !== null) {
    window.clearInterval(appState.indicatorTimer);
    clearIndicator(rooms);
  }
  appState.indicatorTimer = startIndicatorUpdates(rooms, getSelectedEvents, () => appState.filterState.date);

  if (errors.length > 0) {
    setStatusMessage(`Loaded schedule with ${errors.length} source warnings.`, "warning");
  }
}

document.addEventListener("DOMContentLoaded", () => {
  initializeApp().catch((error) => {
    const { rooms } = getElements();
    renderErrorState(rooms, error instanceof Error ? error.message : "Failed to initialize the schedule.");
    setStatusMessage("The schedule could not be loaded.", "error");
  });
});
