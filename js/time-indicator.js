function toDateTime(selectedDate, time) {
  return new Date(`${selectedDate}T${time}:00`);
}

function formatNow(now) {
  return now.toTimeString().slice(0, 5);
}

export function findIndicatorIndex(events, selectedDate, now = new Date()) {
  const sameDayEvents = events.filter((event) => event.date === selectedDate);

  for (let index = 0; index < sameDayEvents.length; index += 1) {
    const event = sameDayEvents[index];
    const eventStart = toDateTime(selectedDate, event.start);
    if (now < eventStart) {
      return index;
    }
  }

  return sameDayEvents.length;
}

export function clearIndicator(container) {
  const indicator = container.querySelector(".time-indicator");
  if (indicator) {
    indicator.remove();
  }
}

export function insertIndicator(container, events, selectedDate, now = new Date()) {
  clearIndicator(container);

  const today = now.toISOString().slice(0, 10);
  if (selectedDate !== today || events.length === 0) {
    return;
  }

  const indicator = document.createElement("div");
  indicator.className = "time-indicator";
  indicator.textContent = `Now - ${formatNow(now)}`;

  const insertionIndex = findIndicatorIndex(events, selectedDate, now);
  const cards = [...container.querySelectorAll(".room-card")];
  const target = cards[insertionIndex] ?? null;
  container.insertBefore(indicator, target);
}

export function startIndicatorUpdates(container, getEvents, getSelectedDate) {
  const render = () => insertIndicator(container, getEvents(), getSelectedDate());
  render();
  return window.setInterval(render, 60_000);
}
