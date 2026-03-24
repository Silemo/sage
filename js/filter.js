function normalizeSearch(value) {
  return String(value ?? "").trim().toLowerCase();
}

function isSelectableTeamName(teamName) {
  return teamName !== "ALL" && teamName !== "Every One" && !teamName.startsWith("Plenary ");
}

export function isGlobalPlenary(event) {
  return event.type === "Plenary" && (
    event.name === "ALL" ||
    event.name === "Every One" ||
    event.vs === ""
  );
}

export function isVsPlenary(event, valueStream) {
  return event.type === "Plenary" && event.vs === valueStream && !isGlobalPlenary(event);
}

function hasSelectableTeams(event) {
  return event.teams.some((teamName) => isSelectableTeamName(teamName));
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

    return left.name.localeCompare(right.name);
  });
}

export function getTeamValueStream(events, teamName) {
  const match = events.find((event) => event.teams.includes(teamName) && hasSelectableTeams(event));
  return match?.vs ?? "";
}

export function buildHierarchy(events) {
  const valueStreamMap = new Map();
  const dates = new Set();
  const types = new Set();

  events.forEach((event) => {
    dates.add(event.date);
    types.add(event.type);

    if (!event.vs || !hasSelectableTeams(event) || isGlobalPlenary(event)) {
      return;
    }

    if (!valueStreamMap.has(event.vs)) {
      valueStreamMap.set(event.vs, new Set());
    }

    event.teams.forEach((teamName) => {
      if (isSelectableTeamName(teamName)) {
        valueStreamMap.get(event.vs).add(teamName);
      }
    });
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

  return [event.name, event.teams.join(" "), event.vs, event.location, event.topics]
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
        || event.teams.includes(filterState.value)
        || event.teams.length === 0;
    }

    return true;
  });

  return sortEventsByStart(filtered);
}
