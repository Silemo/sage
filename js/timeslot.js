function parseTimeToMinutes(timeString) {
  const match = String(timeString ?? "").match(/^(\d{2}):(\d{2})$/);
  if (!match) {
    return null;
  }

  const hours = Number.parseInt(match[1], 10);
  const minutes = Number.parseInt(match[2], 10);

  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
    return null;
  }

  return (hours * 60) + minutes;
}

function formatMinutes(totalMinutes) {
  const minutesInDay = 24 * 60;
  const normalized = ((totalMinutes % minutesInDay) + minutesInDay) % minutesInDay;
  const hours = String(Math.floor(normalized / 60)).padStart(2, "0");
  const minutes = String(normalized % 60).padStart(2, "0");
  return `${hours}:${minutes}`;
}

function sortBucketEvents(events) {
  return [...events].sort((left, right) => {
    const startComparison = String(left.start).localeCompare(String(right.start));
    if (startComparison !== 0) {
      return startComparison;
    }

    const endComparison = String(left.end).localeCompare(String(right.end));
    if (endComparison !== 0) {
      return endComparison;
    }

    return String(left.name).localeCompare(String(right.name));
  });
}

function formatDate(now) {
  const year = String(now.getFullYear());
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function getBucketKey(timeString, bucketMinutes = 30) {
  const totalMinutes = parseTimeToMinutes(timeString);
  if (totalMinutes === null || bucketMinutes <= 0) {
    return "??";
  }

  const bucketStart = Math.floor(totalMinutes / bucketMinutes) * bucketMinutes;
  return formatMinutes(bucketStart);
}

export function formatBucketLabel(bucketKey, bucketMinutes = 30) {
  const totalMinutes = parseTimeToMinutes(bucketKey);
  if (totalMinutes === null || bucketMinutes <= 0) {
    return "Unknown time";
  }

  return `${formatMinutes(totalMinutes)} – ${formatMinutes(totalMinutes + bucketMinutes)}`;
}

export function groupEventsByTimeslot(events, bucketMinutes = 30) {
  const buckets = new Map();

  events.forEach((event) => {
    const bucketKey = getBucketKey(event.start, bucketMinutes);
    if (!buckets.has(bucketKey)) {
      buckets.set(bucketKey, []);
    }

    buckets.get(bucketKey).push(event);
  });

  return [...buckets.entries()]
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
    .map(([bucketKey, bucketEvents]) => ({
      bucketKey,
      bucketLabel: formatBucketLabel(bucketKey, bucketMinutes),
      events: sortBucketEvents(bucketEvents),
    }));
}

/**
 * Finds the index of the first current or upcoming bucket for the selected date.
 *
 * @note Uses the browser's local clock and timezone. The "now" highlight will
 * be offset if the user's timezone differs from the schedule's timezone.
 */
export function findCurrentBucketIndex(buckets, selectedDate, now = new Date()) {
  const today = formatDate(now);
  if (selectedDate !== today || buckets.length === 0) {
    return -1;
  }

  const currentTime = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const currentBucketKey = getBucketKey(currentTime, 30);
  return buckets.findIndex((bucket) => bucket.bucketKey >= currentBucketKey);
}

