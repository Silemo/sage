function normalizeSearch(value) {
  return String(value ?? "").trim().toLowerCase();
}

export function isGlobalPlenary(event) {
  return event.type === "Plenary" && (
    event.team === "ALL" ||
    event.team === "Every One" ||
    event.vs === "" ||
    event.vs === "Portfolio"
  );
}

export function isVsPlenary(event, valueStream) {
  return event.type === "Plenary" && event.vs === valueStream && !isGlobalPlenary(event);
}

function isSelectableTeam(event) {
  return event.team !== "ALL" && event.team !== "Every One" && !event.team.startsWith("Plenary ");
}

export function sortEventsByStart(events) {
  return [...events].sort((left, right) => {
    const startComparison = left.start.localeCompare(right.start);
    if (startComparison !== 0) {
      return startComparison;
    }

    const endComparison = left.end.localeCompare(right.end);
    if (endComparison !== 0) {
      return endComparison;
    }

    return left.team.localeCompare(right.team);
  });
}

export function getTeamValueStream(events, teamName) {
  const match = events.find((event) => event.team === teamName && isSelectableTeam(event));
  return match?.vs ?? "";
}

export function buildHierarchy(events) {
  const valueStreamMap = new Map();
  const dates = new Set();
  const types = new Set();

  events.forEach((event) => {
    dates.add(event.date);
    types.add(event.type);

    if (!event.vs || !isSelectableTeam(event)) {
      return;
    }

    if (!valueStreamMap.has(event.vs)) {
      valueStreamMap.set(event.vs, new Set());
    }

    valueStreamMap.get(event.vs).add(event.team);
  });

  const valueStreams = {};
  [...valueStreamMap.keys()].sort((left, right) => left.localeCompare(right)).forEach((valueStream) => {
    valueStreams[valueStream] = [...valueStreamMap.get(valueStream)].sort((left, right) => left.localeCompare(right));
  });

  return {
    valueStreams,
    dates: [...dates].sort((left, right) => left.localeCompare(right)),
    types: [...types].sort((left, right) => left.localeCompare(right)),
  };
}

function matchesSearch(event, searchText) {
  const search = normalizeSearch(searchText);
  if (!search) {
    return true;
  }

  return [event.team, event.vs, event.location, event.topics]
    .some((value) => normalizeSearch(value).includes(search));
}

export function filterEvents(events, filterState) {
  const scopedEvents = events.filter((event) => event.date === filterState.date);
  const teamValueStream = filterState.mode === "team"
    ? getTeamValueStream(scopedEvents, filterState.value)
    : "";

  const filtered = scopedEvents.filter((event) => {
    if (!matchesSearch(event, filterState.search)) {
      return false;
    }

    if (filterState.mode === "plenary") {
      return isGlobalPlenary(event);
    }

    if (filterState.mode === "vs") {
      return isGlobalPlenary(event) || event.vs === filterState.value;
    }

    if (filterState.mode === "team") {
      return isGlobalPlenary(event)
        || (teamValueStream !== "" && isVsPlenary(event, teamValueStream))
        || event.team === filterState.value;
    }

    return true;
  });

  return sortEventsByStart(filtered);
}
