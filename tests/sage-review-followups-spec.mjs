import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const workspaceRoot = path.resolve(__dirname, "..");
const baseUrl = process.env.SAGE_TEST_BASE_URL ?? "http://127.0.0.1:8000/";
const sourceScriptPath = path.join(workspaceRoot, "tests", "sage-spec-requirements.mjs");
const day2JsonPath = path.join(workspaceRoot, "data", "json", "2026-03-18.json");
const readmePath = path.join(workspaceRoot, "README.md");

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

function runNodeScript(scriptPath) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [scriptPath], {
      cwd: workspaceRoot,
      env: {
        ...process.env,
        SAGE_TEST_BASE_URL: baseUrl,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", reject);
    child.on("close", (code) => {
      resolve({ code: code ?? 1, stdout, stderr });
    });
  });
}

async function withTemporaryDay2Mutation(extraRecord, testFn) {
  const originalContent = await readFile(day2JsonPath, "utf8");
  const records = JSON.parse(originalContent);
  records.push(extraRecord);
  await writeFile(day2JsonPath, `${JSON.stringify(records, null, 2)}\n`, "utf8");

  try {
    await testFn();
  } finally {
    await writeFile(day2JsonPath, originalContent, "utf8");
  }
}

async function withTemporaryScript(sourceText, testFn) {
  const tempPath = path.join(workspaceRoot, "tests", "sage-spec-requirements.temp.mjs");
  await writeFile(tempPath, sourceText, "utf8");

  try {
    await testFn(tempPath);
  } finally {
    await rm(tempPath, { force: true });
  }
}

await runTest("README heading matches SAGE branding", async () => {
  const readme = await readFile(readmePath, "utf8");
  assert.equal(readme.split(/\r?\n/, 1)[0], "# SAGE");
});

await runTest("requirements suite stays green when valid committed data grows", async () => {
  await withTemporaryDay2Mutation(
    {
      time: "17:30-18:00",
      location: "Regression Room",
      topics: "Additional Valid Event",
      team: "Regression Team",
      vs: "PLM",
      type: "Breakout",
    },
    async () => {
      const result = await runNodeScript(sourceScriptPath);

      assert.equal(result.code, 0, result.stderr || result.stdout);
      assert.match(result.stdout, /PASS 5\/5/);
      assert.doesNotMatch(result.stdout, /FAIL:/);
    },
  );
});

await runTest("requirements runner exits non-zero but continues after an early failure", async () => {
  const sourceText = await readFile(sourceScriptPath, "utf8");
  const failingSource = sourceText.replace(
    '  const indexHtml = await fetchText("index.html");',
    '  const indexHtml = await fetchText("index.html");\n  assert.fail("forced early failure");',
  );

  assert.notEqual(failingSource, sourceText, "Expected to patch the first test body in the temporary script copy");

  await withTemporaryScript(failingSource, async (tempPath) => {
    const result = await runNodeScript(tempPath);

    assert.equal(result.code, 1, `Expected non-zero exit code, got ${result.code}\n${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /FAIL: shipped shell shows SAGE branding and no upload control -- forced early failure/);
    assert.match(result.stdout, /PASS: repo uses canonical data folders and logical source names/);
    assert.match(result.stdout, /PASS: loader skips malformed committed CSV rows without aborting the schedule/);
  });
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
process.exit(failCount > 0 ? 1 : 0);