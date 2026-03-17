const STORAGE_KEY = "sage-schedule-preferences";

export function getDefaultDate(availableDates) {
  const today = new Date().toISOString().slice(0, 10);
  if (availableDates.includes(today)) {
    return today;
  }

  return availableDates[0] ?? "";
}

export function normalizeState(rawState, availableDates) {
  const mode = ["all", "plenary", "vs", "team"].includes(rawState.mode) ? rawState.mode : "all";
  const date = availableDates.includes(rawState.date) ? rawState.date : getDefaultDate(availableDates);

  return {
    date,
    mode,
    value: String(rawState.value ?? ""),
    search: String(rawState.search ?? ""),
  };
}

export function readState(availableDates) {
  const searchParams = new URLSearchParams(window.location.search);
  const hasQuery = [...searchParams.keys()].length > 0;
  const storedState = hasQuery ? {} : JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "{}");
  const rawState = {
    date: searchParams.get("date") ?? storedState.date ?? "",
    mode: searchParams.get("mode") ?? storedState.mode ?? "all",
    value: searchParams.get("value") ?? storedState.value ?? "",
    search: searchParams.get("search") ?? storedState.search ?? "",
  };

  return normalizeState(rawState, availableDates);
}

export function writeState(state) {
  const searchParams = new URLSearchParams();

  if (state.date) {
    searchParams.set("date", state.date);
  }
  if (state.mode && state.mode !== "all") {
    searchParams.set("mode", state.mode);
  }
  if (state.value) {
    searchParams.set("value", state.value);
  }
  if (state.search) {
    searchParams.set("search", state.search);
  }

  const query = searchParams.toString();
  const url = query ? `${window.location.pathname}?${query}` : window.location.pathname;
  window.history.replaceState({}, "", url);
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}
