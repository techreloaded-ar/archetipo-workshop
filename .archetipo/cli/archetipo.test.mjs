import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const cliSource = path.join(repoRoot, ".archetipo/cli/archetipo.mjs");

test("create-story reuses an existing US issue and fills project fields", () => {
  const fixture = createFixture({
    issues: [
      issue({ id: "ISSUE_1", number: 1, title: "US-001: Existing story", labels: [] }),
    ],
  });

  try {
    writeJson(path.join(fixture.cwd, "story.json"), {
      code: "US-001",
      title: "US-001: Existing story",
      epic_code: "EP-001",
      epic_title: "Core",
      priority: "HIGH",
      story_points: 3,
      body: "## Story\n\nExisting",
    });

    const result = runCli(fixture, ["create-story", "--input", "story.json", "--json"]);
    assert.equal(result.status, 0, result.stderr);

    const output = JSON.parse(result.stdout);
    assert.equal(output.created[0].action, "reused");
    assert.equal(output.created[0].number, 1);

    const state = readState(fixture);
    assert.equal(state.calls.issueCreate.length, 0);
    assert.equal(state.projectItems.length, 1);
    assert.equal(state.projectItems[0].content.number, 1);
    assert.equal(state.calls.projectItemEdit.length, 4);
    assert.deepEqual(labelsOf(state.issues.find((item) => item.number === 1)).sort(), ["EP-001", "archetipo-spec"]);
  } finally {
    fixture.cleanup();
  }
});

test("create-story rejects duplicate input before creating issues", () => {
  const fixture = createFixture();

  try {
    writeJson(path.join(fixture.cwd, "stories.json"), {
      stories: [
        { code: "US-001", title: "US-001: One", epic_code: "EP-001", epic_title: "Core", priority: "HIGH", story_points: 1, body: "A" },
        { code: "US-001", title: "US-001: Duplicate", epic_code: "EP-001", epic_title: "Core", priority: "HIGH", story_points: 1, body: "B" },
      ],
    });

    const result = runCli(fixture, ["create-story", "--input", "stories.json", "--json"]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /storie duplicate con codice US-001/);
    assert.equal(readState(fixture).calls.issueCreate.length, 0);
  } finally {
    fixture.cleanup();
  }
});

test("create-plan-tasks reuses linked TASK issues and avoids duplicate plan pointers", () => {
  const existingBody = "Original body\n\n## Piano di Implementazione\n\n**File:** `docs/planning/US-001.md`";
  const fixture = createFixture({
    issues: [
      issue({ id: "PARENT", number: 1, title: "US-001: Parent", labels: ["archetipo-spec", "EP-001"], body: existingBody }),
      issue({ id: "TASK_1", number: 2, title: "TASK-01: Implement core", labels: ["subtask", "EP-001"] }),
    ],
    links: { 1: ["TASK_1"] },
    projectItems: [projectItem({ itemId: "ITEM_PARENT", issueNumber: 1 })],
  });

  try {
    writeJson(path.join(fixture.cwd, "plan-tasks.json"), {
      issue: 1,
      plan_file: "docs/planning/US-001.md",
      summary: { total_tasks: 1, implementation_tasks: 1, test_tasks: 0, effort: "S" },
      tasks: [{ id: "TASK-01", title: "TASK-01: Implement core", body: "## Task\n\nDo it" }],
    });

    const result = runCli(fixture, ["create-plan-tasks", "--input", "plan-tasks.json", "--json"]);
    assert.equal(result.status, 0, result.stderr);

    const output = JSON.parse(result.stdout);
    assert.equal(output.children[0].action, "reused");
    assert.equal(output.children[0].number, 2);

    const state = readState(fixture);
    assert.equal(state.calls.issueCreate.length, 0);
    assert.equal(state.calls.subIssuePost.length, 0);
    assert.equal(state.calls.bodyEdits.length, 0);
    assert.equal(state.issues.find((item) => item.number === 1).body, existingBody);
  } finally {
    fixture.cleanup();
  }
});

test("move-story review closes only open linked subtasks", () => {
  const fixture = createFixture({
    issues: [
      issue({ id: "PARENT", number: 1, title: "US-001: Parent", labels: ["archetipo-spec", "EP-001"] }),
      issue({ id: "TASK_1", number: 2, title: "TASK-01: Implement", labels: ["subtask", "EP-001"], state: "OPEN" }),
      issue({ id: "NOTE_1", number: 3, title: "Follow-up note", labels: ["EP-001"], state: "OPEN" }),
    ],
    links: { 1: ["TASK_1", "NOTE_1"] },
    projectItems: [projectItem({ itemId: "ITEM_PARENT", issueNumber: 1 })],
  });

  try {
    const result = runCli(fixture, ["move-story", "--issue", "1", "--status", "review", "--json"]);
    assert.equal(result.status, 0, result.stderr);

    const output = JSON.parse(result.stdout);
    assert.deepEqual(output.closed_subtasks, [2]);

    const state = readState(fixture);
    assert.equal(state.issues.find((item) => item.number === 2).state, "CLOSED");
    assert.equal(state.issues.find((item) => item.number === 3).state, "OPEN");
    assert.deepEqual(state.calls.issueClose, [2]);
  } finally {
    fixture.cleanup();
  }
});

test("incomplete config reports a clear setup error", () => {
  const fixture = createFixture({ writeConfig: false });

  try {
    mkdirSync(path.join(fixture.cwd, ".archetipo"), { recursive: true });
    writeFileSync(path.join(fixture.cwd, ".archetipo/config.yaml"), "github:\n", "utf8");

    const result = runCli(fixture, ["project-items", "--json"]);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Configurazione Archetipo incompleta/);
    assert.doesNotMatch(result.stderr, /Cannot read properties/);
  } finally {
    fixture.cleanup();
  }
});

function createFixture(overrides = {}) {
  const cwd = path.join(tmpdir(), `archetipo-cli-test-${Date.now()}-${Math.random().toString(16).slice(2)}`);
  const bin = path.join(cwd, "bin");
  mkdirSync(path.join(cwd, ".archetipo/cli"), { recursive: true });
  mkdirSync(bin, { recursive: true });
  copyFileSync(cliSource, path.join(cwd, ".archetipo/cli/archetipo.mjs"));
  writeFileSync(path.join(bin, "gh"), fakeGhScript(), { mode: 0o755 });

  if (overrides.writeConfig !== false) {
    writeFileSync(path.join(cwd, ".archetipo/config.yaml"), configYaml(), "utf8");
  }

  const statePath = path.join(cwd, "gh-state.json");
  writeJson(statePath, {
    owner: "octo",
    repo: "repo",
    nextIssueNumber: 100,
    issues: overrides.issues || [],
    links: overrides.links || {},
    projectItems: overrides.projectItems || [],
    fields: defaultFields(),
    calls: {
      issueCreate: [],
      issueClose: [],
      projectItemEdit: [],
      subIssuePost: [],
      bodyEdits: [],
    },
  });

  return {
    cwd,
    env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`, ARCHETIPO_FAKE_GH_STATE: statePath },
    statePath,
    cleanup: () => rmSync(cwd, { recursive: true, force: true }),
  };
}

function runCli(fixture, args) {
  return spawnSync(process.execPath, [".archetipo/cli/archetipo.mjs", ...args], {
    cwd: fixture.cwd,
    env: fixture.env,
    encoding: "utf8",
  });
}

function readState(fixture) {
  return JSON.parse(readFileSync(fixture.statePath, "utf8"));
}

function labelsOf(item) {
  return (item.labels || []).map((label) => (typeof label === "string" ? label : label.name)).filter(Boolean);
}

function writeJson(file, value) {
  writeFileSync(file, JSON.stringify(value, null, 2), "utf8");
}

function issue({ id, number, title, labels = [], state = "OPEN", body = "" }) {
  return {
    id,
    number,
    title,
    labels: labels.map((name) => ({ name })),
    state,
    body,
    url: `https://github.com/octo/repo/issues/${number}`,
    html_url: `https://github.com/octo/repo/issues/${number}`,
  };
}

function projectItem({ itemId, issueNumber }) {
  const itemIssue = issue({ id: `ISSUE_${issueNumber}`, number: issueNumber, title: `US-${String(issueNumber).padStart(3, "0")}: Story` });
  return {
    id: itemId,
    content: itemIssue,
    fieldValues: [{ fieldName: "Status", name: "Todo", optionId: "STATUS_TODO" }],
  };
}

function configYaml() {
  return `github:
  owner: octo
  project_number: 1
  project_node_id: PROJECT_1
  fields:
    status:
      id: FIELD_STATUS
      options:
        todo: STATUS_TODO
        planned: STATUS_PLANNED
        in_progress: STATUS_IN_PROGRESS
        review: STATUS_REVIEW
        done: STATUS_DONE
    priority:
      id: FIELD_PRIORITY
      options:
        high: PRIORITY_HIGH
        medium: PRIORITY_MEDIUM
        low: PRIORITY_LOW
    story_points:
      id: FIELD_POINTS
    epic:
      id: FIELD_EPIC
`;
}

function defaultFields() {
  return [
    { id: "FIELD_STATUS", name: "Status", options: [{ id: "STATUS_TODO", name: "Todo" }, { id: "STATUS_REVIEW", name: "Review" }] },
    { id: "FIELD_PRIORITY", name: "Priority", options: [{ id: "PRIORITY_HIGH", name: "HIGH" }] },
    { id: "FIELD_POINTS", name: "Story Points" },
    { id: "FIELD_EPIC", name: "Epic", options: [{ id: "EPIC_1", name: "EP-001: Core" }] },
  ];
}

function fakeGhScript() {
  return `#!/usr/bin/env node
const fs = require("fs");
const path = process.env.ARCHETIPO_FAKE_GH_STATE;
const args = process.argv.slice(2);
const state = JSON.parse(fs.readFileSync(path, "utf8"));
function save() { fs.writeFileSync(path, JSON.stringify(state, null, 2)); }
function out(value) { process.stdout.write(typeof value === "string" ? value : JSON.stringify(value)); }
function argAfter(name) { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; }
function labelsOf(issue) { return (issue.labels || []).map((label) => typeof label === "string" ? label : label.name); }
function issueByNumber(number) { return state.issues.find((issue) => String(issue.number) === String(number)); }
function issueById(id) { return state.issues.find((issue) => String(issue.id) === String(id)); }
function selected(issue, fields) {
  if (!fields) return issue;
  const result = {};
  for (const field of fields.split(",")) result[field] = issue[field];
  return result;
}
if (args[0] === "repo" && args[1] === "view") {
  if ((argAfter("--json") || "").includes("owner")) out({ owner: { login: state.owner } });
  else out({ name: state.repo });
} else if (args[0] === "project" && args[1] === "field-list") {
  out({ fields: state.fields });
} else if (args[0] === "project" && args[1] === "item-list") {
  out({ items: state.projectItems });
} else if (args[0] === "project" && args[1] === "item-edit") {
  state.calls.projectItemEdit.push(args);
  const item = state.projectItems.find((candidate) => candidate.id === argAfter("--id"));
  if (item) {
    const fieldId = argAfter("--field-id");
    const value = argAfter("--single-select-option-id") || argAfter("--number");
    item.fieldValues = item.fieldValues || [];
    item.fieldValues.push({ field: { id: fieldId }, id: value, optionId: value, value, number: Number(value) || undefined });
  }
  save();
} else if (args[0] === "api" && args[1] === "graphql") {
  const payload = JSON.parse(fs.readFileSync(argAfter("--input"), "utf8"));
  if (payload.query.includes("addProjectV2ItemById")) {
    const issue = issueById(payload.variables.c);
    let item = state.projectItems.find((candidate) => candidate.content && candidate.content.id === issue.id);
    if (!item) {
      item = { id: "ITEM_" + issue.number, content: issue, fieldValues: [] };
      state.projectItems.push(item);
    }
    save();
    out({ data: { addProjectV2ItemById: { item: { id: item.id } } } });
  } else {
    out({ data: {} });
  }
} else if (args[0] === "label" && args[1] === "create") {
  out("");
} else if (args[0] === "issue" && args[1] === "list") {
  const search = argAfter("--search") || "";
  const code = (search.match(/(US-\\d{3}|TASK-\\d{2,3})/) || [])[1];
  out(state.issues.filter((issue) => issue.title.includes(code)));
} else if (args[0] === "issue" && args[1] === "create") {
  const title = argAfter("--title");
  const labels = args.flatMap((arg, index) => arg === "--label" ? [args[index + 1]] : []).filter(Boolean);
  const number = state.nextIssueNumber++;
  const created = { id: "ISSUE_" + number, number, title, labels: labels.map((name) => ({ name })), state: "OPEN", body: "", url: "https://github.com/octo/repo/issues/" + number, html_url: "https://github.com/octo/repo/issues/" + number };
  state.issues.push(created);
  state.calls.issueCreate.push(number);
  save();
  out(created.html_url);
} else if (args[0] === "issue" && args[1] === "view") {
  out(selected(issueByNumber(args[2]), argAfter("--json")));
} else if (args[0] === "issue" && args[1] === "edit") {
  const issue = issueByNumber(args[2]);
  const label = argAfter("--add-label");
  const bodyFile = argAfter("--body-file");
  if (label && !labelsOf(issue).includes(label)) issue.labels.push({ name: label });
  if (bodyFile) {
    issue.body = fs.readFileSync(bodyFile, "utf8");
    state.calls.bodyEdits.push(Number(issue.number));
  }
  save();
} else if (args[0] === "issue" && args[1] === "close") {
  const issue = issueByNumber(args[2]);
  issue.state = "CLOSED";
  state.calls.issueClose.push(Number(issue.number));
  save();
} else if (args[0] === "api" && args[1] && args[1].includes("/issues/") && !args.includes("-X")) {
  const match = args[1].match(/issues\\/(\\d+)(?:\\/(sub_issues))?/);
  if (match[2]) {
    const linkedIds = state.links[match[1]] || [];
    out(linkedIds.map(issueById).filter(Boolean));
  } else {
    out(issueByNumber(match[1]));
  }
} else if (args[0] === "api" && args.includes("-X") && args.includes("POST")) {
  const pathArg = args.find((arg) => arg.includes("/sub_issues"));
  const parent = pathArg.match(/issues\\/(\\d+)\\/sub_issues/)[1];
  const childId = (args.find((arg) => arg.startsWith("sub_issue_id=")) || "").split("=")[1];
  state.links[parent] = state.links[parent] || [];
  if (!state.links[parent].includes(childId)) {
    state.links[parent].push(childId);
    state.calls.subIssuePost.push({ parent: Number(parent), childId });
  }
  save();
  out({});
} else {
  console.error("Unhandled fake gh command: gh " + args.join(" "));
  process.exit(1);
}
`;
}
