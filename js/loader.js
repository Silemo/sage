const REQUIRED_FIELDS = ["date", "start", "end", "name", "topics", "location", "type"];
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^\d{2}:\d{2}$/;
const VS_ALIASES = {
  "all": "Portfolio",
  "experimentation runway": "Exp RW",
  "exp runway": "Exp RW",
  "exp rw": "Exp RW",
};
const TEAM_ALIASES = {
  "Plenary Exp Runway": "Plenary Exp RW",
};

function normalizeWhitespace(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

export function normalizeVsName(valueStream) {
  const normalized = normalizeWhitespace(valueStream);
  if (normalized === "") {
    return "";
  }

  return VS_ALIASES[normalized.toLowerCase()] ?? normalized;
}

export function normalizeTeamName(teamName) {
  const normalized = normalizeWhitespace(teamName);
  return TEAM_ALIASES[normalized] ?? normalized;
}

function parseTeams(rawTeams) {
  const normalized = normalizeWhitespace(rawTeams);
  if (normalized === "") {
    return [];
  }

  return normalized
    .split(",")
    .map((teamName) => normalizeTeamName(teamName))
    .filter((teamName) => teamName !== "");
}

function normalizeType(type) {
  const normalized = normalizeWhitespace(type);
  if (normalized === "") {
    return "";
  }

  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

function normalizeTimeValue(timeValue) {
  const normalized = normalizeWhitespace(timeValue);
  const match = normalized.match(/^(\d{1,2}):(\d{2})$/);

  if (!match) {
    return normalized;
  }

  const [, hours, minutes] = match;
  return `${hours.padStart(2, "0")}:${minutes}`;
}

function splitTimeRange(timeRange) {
  const normalized = normalizeWhitespace(timeRange);
  if (!normalized.includes("-")) {
    return { start: "", end: "" };
  }

  const [start, end] = normalized.split("-").map((part) => normalizeTimeValue(part));
  return { start, end };
}

function escapeCsvCell(cell) {
  return normalizeWhitespace(cell).replace(/^"|"$/g, "");
}

export function parseCsv(csvText) {
  const rows = [];
  let currentValue = "";
  let currentRow = [];
  let insideQuotes = false;
  const normalizedText = String(csvText ?? "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  for (let index = 0; index < normalizedText.length; index += 1) {
    const char = normalizedText[index];
    const nextChar = normalizedText[index + 1];

    if (char === '"') {
      if (insideQuotes && nextChar === '"') {
        currentValue += '"';
        index += 1;
      } else {
        insideQuotes = !insideQuotes;
      }
      continue;
    }

    if (char === "," && !insideQuotes) {
      currentRow.push(escapeCsvCell(currentValue));
      currentValue = "";
      continue;
    }

    if (char === "\n" && !insideQuotes) {
      currentRow.push(escapeCsvCell(currentValue));
      if (currentRow.some((cell) => cell !== "")) {
        rows.push(currentRow);
      }
      currentRow = [];
      currentValue = "";
      continue;
    }

    currentValue += char;
  }

  if (currentValue !== "" || currentRow.length > 0) {
    currentRow.push(escapeCsvCell(currentValue));
    if (currentRow.some((cell) => cell !== "")) {
      rows.push(currentRow);
    }
  }

  if (rows.length === 0) {
    return [];
  }

  const header = rows[0].map((column) => column.toLowerCase());
  return rows.slice(1).map((row) => {
    const record = {};
    header.forEach((column, index) => {
      record[column] = row[index] ?? "";
    });
    return record;
  });
}

export function createEventId(record) {
  const seed = [record.date, record.start, record.end, record.name, record.location, record.topics].join("|");
  let hash = 0;

  for (let index = 0; index < seed.length; index += 1) {
    hash = ((hash << 5) - hash + seed.charCodeAt(index)) | 0;
  }

  return `event-${Math.abs(hash)}`;
}

export function validateRecord(record) {
  const errors = [];

  REQUIRED_FIELDS.forEach((field) => {
    if (normalizeWhitespace(record[field]) === "") {
      errors.push(`Missing ${field}`);
    }
  });

  if (record.date && !DATE_PATTERN.test(record.date)) {
    errors.push("Invalid date format");
  }

  if (record.start && !TIME_PATTERN.test(record.start)) {
    errors.push("Invalid start time format");
  }

  if (record.end && !TIME_PATTERN.test(record.end)) {
    errors.push("Invalid end time format");
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

export function normalizeRecord(rawRecord, sourceName = "unknown", defaultDate = "") {
  const timeRange = normalizeWhitespace(rawRecord.time);
  const splitTime = splitTimeRange(timeRange);
  const date = normalizeWhitespace(rawRecord.date) || defaultDate;
  const normalizedRecord = {
    date: normalizeWhitespace(date),
    start: normalizeTimeValue(rawRecord.start) || splitTime.start,
    end: normalizeTimeValue(rawRecord.end) || splitTime.end,
    name: normalizeWhitespace(rawRecord.name ?? rawRecord.team),
    teams: parseTeams(rawRecord.teams ?? rawRecord.team),
    vs: normalizeVsName(rawRecord.vs ?? rawRecord["value stream"]),
    topics: normalizeWhitespace(rawRecord.topics ?? rawRecord.product),
    location: normalizeWhitespace(rawRecord.location),
    type: normalizeType(rawRecord.type),
    source: sourceName,
  };
  const validation = validateRecord(normalizedRecord);

  if (!validation.valid) {
    return {
      record: null,
      errors: validation.errors,
    };
  }

  const record = {
    ...normalizedRecord,
    id: normalizeWhitespace(rawRecord.id) || createEventId(normalizedRecord),
  };

  return {
    record,
    errors: [],
  };
}

async function fetchSourceText(path) {
  const response = await fetch(path);

  if (!response.ok) {
    throw new Error(`Failed to load ${path}: ${response.status}`);
  }

  return response.text();
}

export async function loadJsonSource(path) {
  const response = await fetch(path);

  if (!response.ok) {
    throw new Error(`Failed to load ${path}: ${response.status}`);
  }

  const data = await response.json();
  if (!Array.isArray(data)) {
    throw new Error(`Expected an array in ${path}`);
  }

  return data;
}

async function loadSourceRecords(sourceConfig) {
  const fileStem = normalizeWhitespace(sourceConfig.file ?? sourceConfig.defaultDate);
  const csvPath = `data/csv/${fileStem}.csv`;
  const jsonPath = `data/json/${fileStem}.json`;

  try {
    const csvText = await fetchSourceText(csvPath);
    return {
      records: parseCsv(csvText),
      sourceLabel: csvPath,
    };
  } catch (csvError) {
    try {
      const jsonRecords = await loadJsonSource(jsonPath);
      return {
        records: jsonRecords,
        sourceLabel: jsonPath,
      };
    } catch (jsonError) {
      const csvMessage = csvError instanceof Error ? csvError.message : `Failed to load ${csvPath}`;
      const jsonMessage = jsonError instanceof Error ? jsonError.message : `Failed to load ${jsonPath}`;
      throw new Error(`${csvMessage}; ${jsonMessage}`);
    }
  }
}

export async function loadAllSources(sourcesConfig) {
  const events = [];
  const errors = [];
  const seenIds = new Set();

  for (const sourceConfig of sourcesConfig.sources ?? []) {
    try {
      const { records, sourceLabel } = await loadSourceRecords(sourceConfig);
      for (const rawRecord of records) {
        const { record, errors: recordErrors } = normalizeRecord(rawRecord, sourceLabel, sourceConfig.defaultDate);
        if (!record) {
          errors.push(`${sourceLabel}: ${recordErrors.join(", ")}`);
          continue;
        }
        if (!seenIds.has(record.id)) {
          seenIds.add(record.id);
          events.push(record);
        }
      }
    } catch (error) {
      const sourceLabel = sourceConfig.label ?? sourceConfig.defaultDate;
      errors.push(error instanceof Error ? error.message : `Failed to load source ${sourceLabel}`);
    }
  }

  return {
    events,
    errors,
  };
}
