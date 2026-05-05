#!/usr/bin/env node

import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const STATUS_OPTIONS = ["Todo", "Planned", "In Progress", "Review", "Done"];
const PRIORITY_OPTIONS = ["HIGH", "MEDIUM", "LOW"];
const STATUS_KEYS = {
  todo: "Todo",
  planned: "Planned",
  in_progress: "In Progress",
  review: "Review",
  done: "Done",
};

main();

function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);

  try {
    switch (command) {
      case "setup-project":
        setupProject(args);
        break;
      case "project-items":
        projectItems(args);
        break;
      case "issue-view":
        issueViewCommand(args);
        break;
      case "sync-epics":
        syncEpicsCommand(args);
        break;
      case "create-story":
        createStoryCommand(args);
        break;
      case "create-plan-tasks":
        createPlanTasksCommand(args);
        break;
      case "move-story":
        moveStoryCommand(args);
        break;
      case "comment-story":
        commentStoryCommand(args);
        break;
      case "help":
      case "--help":
      case "-h":
      case undefined:
        printHelp();
        break;
      default:
        fail(`Unknown command: ${command}`);
    }
  } catch (error) {
    fail(error.message);
  }
}

function printHelp() {
  console.log(`Archetipo GitHub Projects CLI

Usage:
  node .archetipo/cli/archetipo.mjs setup-project
  node .archetipo/cli/archetipo.mjs project-items [--label archetipo-spec] [--status todo] [--json]
  node .archetipo/cli/archetipo.mjs issue-view --issue 12 [--json]
  node .archetipo/cli/archetipo.mjs sync-epics --input epics.json [--json]
  node .archetipo/cli/archetipo.mjs create-story --input story.json [--json]
  node .archetipo/cli/archetipo.mjs create-plan-tasks --input plan-tasks.json [--json]
  node .archetipo/cli/archetipo.mjs move-story --issue 12 --status review [--json]
  node .archetipo/cli/archetipo.mjs comment-story --issue 12 --body-file summary.md [--json]

All GitHub operations use the local GitHub CLI auth/session. Run "gh auth login"
and "gh auth refresh -s read:project -s project" when project scopes are missing.`);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      args._.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    i += 1;
  }
  return args;
}

function setupProject(args) {
  assertPrerequisites();

  const repo = getRepo();
  assertProjectScopes(repo.owner);

  const projectTitle = args.title || `${repo.name} Backlog`;
  info(`Configuro GitHub Project per Archetipo: ${projectTitle}`);

  const created = ghJson(["project", "create", "--owner", repo.owner, "--title", projectTitle, "--format", "json"]);
  const projectNumber = String(created.number || "");
  if (!projectNumber) {
    fail("Creazione GitHub Project non completata: numero progetto mancante.");
  }

  const project = ghJson(["project", "view", projectNumber, "--owner", repo.owner, "--format", "json"]);
  const projectNodeId = project.id;
  if (!projectNodeId) {
    fail("Creazione GitHub Project non completata: project node id mancante.");
  }

  let fields = getProjectFields(projectNumber, repo.owner);
  const statusField = findField(fields, "Status");
  if (!statusField?.id) {
    fail("Non trovo il campo Status nel GitHub Project appena creato.");
  }

  updateSingleSelectOptions(statusField.id, STATUS_OPTIONS.map((name) => ({ name, color: statusColor(name), description: "" })));
  fields = getProjectFields(projectNumber, repo.owner);

  const priorityFieldId = ensureProjectField(projectNumber, repo.owner, fields, "Priority", "SINGLE_SELECT", [
    "--data-type",
    "SINGLE_SELECT",
    "--single-select-options",
    PRIORITY_OPTIONS.join(","),
  ]);
  fields = getProjectFields(projectNumber, repo.owner);

  const storyPointsFieldId = ensureProjectField(projectNumber, repo.owner, fields, "Story Points", "NUMBER", [
    "--data-type",
    "NUMBER",
  ]);
  fields = getProjectFields(projectNumber, repo.owner);

  const epicFieldId = ensureProjectField(projectNumber, repo.owner, fields, "Epic", "SINGLE_SELECT", [
    "--data-type",
    "SINGLE_SELECT",
    "--single-select-options",
    "EP-000: placeholder",
  ]);

  fields = getProjectFields(projectNumber, repo.owner);
  const freshStatusField = findField(fields, "Status");
  const priorityField = findField(fields, "Priority");
  if (!freshStatusField?.id || !priorityField?.id) {
    fail("Non riesco a rileggere i campi Status/Priority dopo la configurazione.");
  }

  const config = {
    github: {
      owner: repo.owner,
      project_number: projectNumber,
      project_node_id: projectNodeId,
      fields: {
        status: {
          id: freshStatusField.id,
          options: {
            todo: optionId(freshStatusField, "Todo"),
            planned: optionId(freshStatusField, "Planned"),
            in_progress: optionId(freshStatusField, "In Progress"),
            review: optionId(freshStatusField, "Review"),
            done: optionId(freshStatusField, "Done"),
          },
        },
        priority: {
          id: priorityFieldId,
          options: {
            high: optionId(priorityField, "HIGH"),
            medium: optionId(priorityField, "MEDIUM"),
            low: optionId(priorityField, "LOW"),
          },
        },
        story_points: { id: storyPointsFieldId },
        epic: { id: epicFieldId },
      },
    },
  };

  validateConfig(config);
  ghText(["label", "create", "archetipo-spec", "--description", "Story generated by /archetipo-spec", "--color", "0E8A16", "--force"]);
  writeConfig(config);

  const result = {
    owner: repo.owner,
    repo: repo.name,
    project_number: projectNumber,
    project_node_id: projectNodeId,
    config_path: ".archetipo/config.yaml",
  };

  output(args, result, `GitHub Project configurato: ${projectTitle} (#${projectNumber})\nConfig scritto in .archetipo/config.yaml`);
}

function projectItems(args) {
  const config = loadConfig();
  const items = getProjectItems(config, numberArg(args.limit, 200));
  const filtered = items
    .filter((item) => !args.label || labelsOf(item).includes(args.label))
    .filter((item) => !args.status || statusMatches(config, item, args.status))
    .map(normalizeProjectItem);

  output(args, { count: filtered.length, items: filtered }, `Project items: ${filtered.length}`);
}

function issueViewCommand(args) {
  const issue = required(args.issue, "--issue");
  const result = ghJson(["issue", "view", String(issue), "--json", "body,title,labels,number,url,id"]);
  output(args, result, `Issue #${result.number}: ${result.title}`);
}

function syncEpicsCommand(args) {
  const input = readInput(args.input);
  const epics = normalizeEpics(input.epics || input);
  const config = loadConfig();
  const result = syncEpics(config, epics);
  output(args, result, `Epic sincronizzati: ${result.epics.length}`);
}

function createStoryCommand(args) {
  const input = readInput(args.input);
  const stories = Array.isArray(input.stories) ? input.stories : [input];
  const config = loadConfig();
  const created = [];

  for (const story of stories) {
    const result = createStory(config, story);
    created.push(result);
  }

  output(args, { created }, `Issue create: ${created.map((item) => `#${item.number}`).join(", ")}`);
}

function createPlanTasksCommand(args) {
  const input = readInput(args.input);
  const config = loadConfig();
  const repo = getRepo(config.github.owner);
  const issueNumber = required(input.issue || input.parent_issue, "input.issue");
  const planFile = required(input.plan_file, "input.plan_file");
  const summary = input.summary || {};
  const tasks = requiredArray(input.tasks, "input.tasks");
  const parentIssue = ghJson(["issue", "view", String(issueNumber), "--json", "body,title,labels,number,url"]);
  const epicLabel = input.epic_label || findEpicLabel(parentIssue.labels);

  if (!epicLabel) {
    fail(`Issue #${issueNumber} non ha una label EP-XXX stabile.`);
  }

  ghText(["label", "create", "subtask", "--description", "Technical subtask of a user story", "--color", "C2E0C6", "--force"]);

  const children = tasks.map((task) => {
    const body = required(task.body, `task ${task.id || task.title} body`);
    const rawTitle = required(task.title, "task.title");
    const title = rawTitle.startsWith("TASK-") ? rawTitle : `${required(task.id, "task.id")}: ${rawTitle}`;
    const bodyFile = withTempFile("task-body", ".md", body, (file) =>
      ghText(["issue", "create", "--title", title, "--label", "subtask", "--label", epicLabel, "--body-file", file]),
    );
    const childNumber = issueNumberFromText(bodyFile);
    const child = ghJson(["api", `repos/${config.github.owner}/${repo.name}/issues/${childNumber}`]);
    ghJson([
      "api",
      "-X",
      "POST",
      `repos/${config.github.owner}/${repo.name}/issues/${issueNumber}/sub_issues`,
      "-F",
      `sub_issue_id=${child.id}`,
      "-H",
      "X-GitHub-Api-Version: 2022-11-28",
    ]);
    return { number: childNumber, title, url: child.html_url };
  });

  const pointer = buildPlanPointer(planFile, summary, input.footer);
  const updatedBody = `${parentIssue.body || ""}\n\n${pointer}`;
  withTempFile("updated-body", ".md", updatedBody, (file) => ghText(["issue", "edit", String(issueNumber), "--body-file", file]));

  ghText(["label", "create", "planned", "--description", "Story has an implementation plan", "--color", "0E8A16", "--force"]);
  ghText(["issue", "edit", String(issueNumber), "--add-label", "planned"]);
  moveStory(config, issueNumber, "planned");

  output(args, { issue: Number(issueNumber), children }, `Pianificazione completata: ${children.length} sub-issues create.`);
}

function moveStoryCommand(args) {
  const issue = required(args.issue, "--issue");
  const status = required(args.status, "--status");
  const config = loadConfig();
  const result = moveStory(config, issue, status);
  output(args, result, `Issue #${issue} spostata a ${result.status}.`);
}

function commentStoryCommand(args) {
  const issue = required(args.issue, "--issue");
  const bodyFile = required(args["body-file"], "--body-file");
  assertReadable(bodyFile);
  ghText(["issue", "comment", String(issue), "--body-file", bodyFile]);
  output(args, { issue: Number(issue), body_file: bodyFile }, `Commento aggiunto a #${issue}.`);
}

function createStory(config, story) {
  const rawTitle = required(story.title, "story.title");
  const storyCode = story.code || codeFromTitle(rawTitle);
  const title = rawTitle.startsWith("US-") ? rawTitle : `${required(storyCode, "story.code")}: ${rawTitle}`;
  const epicCode = required(story.epic_code || codeFromEpic(story.epic), "story.epic_code");
  const epicTitle = story.epic_title || story.epic || epicCode;
  const priority = required(story.priority, "story.priority").toLowerCase();
  const storyPoints = Number(required(story.story_points ?? story.points, "story.story_points"));
  const body = required(story.body, "story.body");
  if (!Number.isFinite(storyPoints)) {
    fail(`Story points non validi: ${story.story_points ?? story.points}`);
  }

  const epicResult = syncEpics(config, [{ code: epicCode, title: epicTitle }]);
  const epicOption = epicResult.byCode[epicCode];
  const priorityOption = config.github.fields.priority.options[priority];
  if (!priorityOption) {
    fail(`Priority non valida: ${story.priority}. Valori: HIGH, MEDIUM, LOW.`);
  }

  const issueUrl = withTempFile("story-body", ".md", body, (file) =>
    ghText(["issue", "create", "--title", title, "--label", "archetipo-spec", "--label", epicCode, "--body-file", file]),
  );
  const issueNumber = issueNumberFromText(issueUrl);
  const issue = ghJson(["issue", "view", String(issueNumber), "--json", "id,number,title,url"]);
  const added = addIssueToProject(config, issue.id);
  const itemId = added.data?.addProjectV2ItemById?.item?.id;
  if (!itemId) {
    fail(`Issue #${issueNumber} creata, ma item project non restituito.`);
  }

  editSingleSelect(config.github.project_node_id, itemId, config.github.fields.status.id, config.github.fields.status.options.todo);
  editSingleSelect(config.github.project_node_id, itemId, config.github.fields.priority.id, priorityOption);
  ghText([
    "project",
    "item-edit",
    "--project-id",
    config.github.project_node_id,
    "--id",
    itemId,
    "--field-id",
    config.github.fields.story_points.id,
    "--number",
    String(storyPoints),
  ]);
  editSingleSelect(config.github.project_node_id, itemId, config.github.fields.epic.id, epicOption.id);

  return {
    number: issue.number,
    title: issue.title,
    url: issue.url,
    item_id: itemId,
    epic: epicOption.name,
    priority: story.priority.toUpperCase(),
    story_points: storyPoints,
  };
}

function syncEpics(config, epics) {
  if (epics.length === 0) {
    return { epics: [], byCode: {} };
  }

  const fields = getProjectFields(config.github.project_number, config.github.owner);
  const epicField = findField(fields, "Epic");
  if (!epicField?.id) {
    fail("Campo Epic non trovato nel GitHub Project.");
  }

  const currentOptions = (epicField.options || []).filter((option) => option.name !== "EP-000: placeholder");
  const byName = new Map(currentOptions.map((option) => [option.name, option]));
  for (const epic of epics) {
    const name = epicOptionName(epic);
    if (!byName.has(name)) {
      byName.set(name, { name, color: "GRAY", description: "" });
    }
  }

  const options = [...byName.values()].map((option) => ({
    name: option.name,
    color: option.color || "GRAY",
    description: option.description || "",
  }));

  updateSingleSelectOptions(config.github.fields.epic.id, options);
  const updatedField = findField(getProjectFields(config.github.project_number, config.github.owner), "Epic");
  const byCode = {};

  for (const epic of epics) {
    const code = required(epic.code || codeFromEpic(epic.name || epic.title), "epic.code");
    const name = epicOptionName(epic);
    const option = (updatedField.options || []).find((item) => item.name === name);
    if (!option?.id) {
      fail(`Opzione Epic non trovata dopo sync: ${name}`);
    }
    ghText(["label", "create", code, "--description", epic.title || name, "--color", "C0C0C0", "--force"]);
    byCode[code] = option;
  }

  return {
    epics: Object.entries(byCode).map(([code, option]) => ({ code, id: option.id, name: option.name })),
    byCode,
  };
}

function moveStory(config, issueNumber, statusKey) {
  const normalizedStatus = normalizeStatus(statusKey);
  const optionIdValue = config.github.fields.status.options[normalizedStatus.key];
  if (!optionIdValue) {
    fail(`Status non configurato: ${statusKey}`);
  }

  const items = getProjectItems(config, 500);
  const item = items.find((candidate) => String(candidate.content?.number) === String(issueNumber));
  if (!item?.id) {
    fail(`Issue #${issueNumber} non trovata nel GitHub Project configurato.`);
  }

  editSingleSelect(config.github.project_node_id, item.id, config.github.fields.status.id, optionIdValue);
  return { issue: Number(issueNumber), item_id: item.id, status: normalizedStatus.name };
}

function getProjectItems(config, limit = 200) {
  const result = ghJson([
    "project",
    "item-list",
    config.github.project_number,
    "--owner",
    config.github.owner,
    "--format",
    "json",
    "-L",
    String(limit),
  ]);
  return result.items || [];
}

function normalizeProjectItem(item) {
  return {
    id: item.id,
    title: item.content?.title || item.title,
    number: item.content?.number,
    url: item.content?.url,
    labels: labelsOf(item),
    status: item.status || fieldValue(item, "Status"),
    priority: item.priority || fieldValue(item, "Priority"),
    story_points: item["Story Points"] || item.storyPoints || fieldValue(item, "Story Points"),
    epic: item.epic || fieldValue(item, "Epic"),
  };
}

function addIssueToProject(config, issueNodeId) {
  return ghGraphql({
    query: "mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}",
    variables: { p: config.github.project_node_id, c: issueNodeId },
  });
}

function editSingleSelect(projectId, itemId, fieldId, optionIdValue) {
  for (const [name, value] of Object.entries({ projectId, itemId, fieldId, optionIdValue })) {
    if (!value) {
      fail(`Valore mancante per item-edit: ${name}`);
    }
  }
  ghText([
    "project",
    "item-edit",
    "--project-id",
    projectId,
    "--id",
    itemId,
    "--field-id",
    fieldId,
    "--single-select-option-id",
    optionIdValue,
  ]);
}

function updateSingleSelectOptions(fieldId, options) {
  ghGraphql({
    query:
      "mutation($f:ID!,$opts:[ProjectV2SingleSelectFieldOptionInput!]!){ updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:$opts}){ projectV2Field { ... on ProjectV2SingleSelectField { id options { id name color description } } } } }",
    variables: { f: fieldId, opts: options },
  });
}

function getProjectFields(projectNumber, owner) {
  const result = ghJson(["project", "field-list", String(projectNumber), "--owner", owner, "--format", "json"]);
  return result.fields || [];
}

function ensureProjectField(projectNumber, owner, fields, name, expectedType, createArgs) {
  const existing = findField(fields, name);
  if (existing) {
    const fieldType = existing.dataType || existing.type || "";
    if (fieldType && fieldType !== expectedType) {
      fail(`Il campo '${name}' esiste gia' ma ha tipo '${fieldType}' invece di '${expectedType}'.`);
    }
    return existing.id;
  }

  ghText(["project", "field-create", String(projectNumber), "--owner", owner, "--name", name, ...createArgs]);
  const created = findField(getProjectFields(projectNumber, owner), name);
  if (!created?.id) {
    fail(`Campo '${name}' non trovato dopo la creazione.`);
  }
  return created.id;
}

function findField(fields, name) {
  return fields.find((field) => field.name === name);
}

function optionId(field, name) {
  const option = (field?.options || []).find((item) => item.name.toLowerCase() === name.toLowerCase());
  return option?.id || "";
}

function labelsOf(item) {
  const labels = item.content?.labels || item.labels || [];
  return labels.map((label) => (typeof label === "string" ? label : label.name)).filter(Boolean);
}

function fieldValue(item, fieldName) {
  const field = (item.fieldValues || []).find((value) => value.fieldName === fieldName || value.field?.name === fieldName);
  return field?.name ?? field?.text ?? field?.number ?? field?.value ?? "";
}

function statusMatches(config, item, status) {
  const normalized = normalizeStatus(status);
  const configuredId = config.github.fields.status.options[normalized.key];
  const field = (item.fieldValues || []).find((value) => value.fieldName === "Status" || value.field?.name === "Status");
  return (
    item.status === normalized.name ||
    field?.optionId === configuredId ||
    field?.id === configuredId ||
    field?.name === normalized.name ||
    fieldValue(item, "Status") === normalized.name
  );
}

function normalizeStatus(status) {
  const key = String(status).trim().toLowerCase().replace(/[-\s]+/g, "_");
  if (!STATUS_KEYS[key]) {
    fail(`Status non valido: ${status}. Valori: ${Object.keys(STATUS_KEYS).join(", ")}`);
  }
  return { key, name: STATUS_KEYS[key] };
}

function statusColor(name) {
  return {
    Todo: "GRAY",
    Planned: "BLUE",
    "In Progress": "YELLOW",
    Review: "PURPLE",
    Done: "GREEN",
  }[name];
}

function getRepo(ownerFallback) {
  const owner = ghJson(["repo", "view", "--json", "owner"]).owner?.login || ownerFallback;
  const name = ghJson(["repo", "view", "--json", "name"]).name;
  if (!owner || !name) {
    fail("Non riesco a rilevare owner e nome del repository GitHub dal remote origin.");
  }
  return { owner, name };
}

function assertPrerequisites() {
  assertCommand("git", ["--version"], "git non e' installato. Installalo prima di continuare.");
  assertCommand("gh", ["--version"], "GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'.");
  ghText(["auth", "status"], { quiet: true, errorMessage: "GitHub CLI non e' autenticata. Esegui: gh auth login" });
}

function assertProjectScopes(owner) {
  const result = spawnSync("gh", ["project", "list", "--owner", owner, "--limit", "1", "--format", "json"], {
    encoding: "utf8",
    shell: false,
  });
  if (result.status !== 0) {
    fail("Mancano gli scope per accedere ai GitHub Projects.\nEsegui: gh auth refresh -s read:project -s project\nPoi rilancia lo script di setup.");
  }
}

function assertCommand(command, args, errorMessage) {
  const result = spawnSync(command, args, { encoding: "utf8", shell: false });
  if (result.error || result.status !== 0) {
    fail(errorMessage);
  }
}

function ghJson(args, options = {}) {
  const output = ghText(args, options);
  try {
    return JSON.parse(output || "{}");
  } catch {
    fail(`Output gh non JSON per: gh ${args.join(" ")}\n${output}`);
  }
}

function ghText(args, options = {}) {
  const maxRetries = options.retries ?? 1;
  let last;
  for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
    const result = spawnSync("gh", args, { encoding: "utf8", shell: false });
    last = result;
    if (result.status === 0) {
      return (result.stdout || "").trim();
    }
  }

  if (options.quiet) {
    fail(options.errorMessage || "Comando gh fallito.");
  }

  const stderr = (last.stderr || last.stdout || "").trim();
  fail(`${options.errorMessage || `Comando gh fallito: gh ${args.join(" ")}`}\n${stderr}`);
}

function ghGraphql(payload) {
  return withTempFile("graphql", ".json", JSON.stringify(payload), (file) => ghJson(["api", "graphql", "--input", file]));
}

function withTempFile(prefix, ext, content, callback) {
  const dir = mkdtempSync(path.join(tmpdir(), "archetipo-"));
  const file = path.join(dir, `${prefix}${ext}`);
  try {
    writeFileSync(file, content, "utf8");
    return callback(file);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function readInput(file) {
  const inputPath = required(file, "--input");
  assertReadable(inputPath);
  try {
    return JSON.parse(readFileSync(inputPath, "utf8"));
  } catch (error) {
    fail(`Input JSON non valido: ${inputPath}\n${error.message}`);
  }
}

function assertReadable(file) {
  try {
    readFileSync(file, "utf8");
  } catch {
    fail(`File non leggibile: ${file}`);
  }
}

function readConfigFile() {
  const file = ".archetipo/config.yaml";
  assertReadable(file);
  return readFileSync(file, "utf8");
}

function loadConfig() {
  const config = parseConfig(readConfigFile());
  validateConfig(config);
  return config;
}

function parseConfig(content) {
  const root = {};
  const stack = [{ indent: -1, value: root }];

  for (const line of content.split(/\r?\n/)) {
    if (!line.trim() || line.trimStart().startsWith("#")) {
      continue;
    }

    const match = line.match(/^(\s*)([^:#]+):(?:\s*(.*))?$/);
    if (!match) {
      continue;
    }

    const indent = match[1].length;
    const key = match[2].trim();
    const rawValue = (match[3] || "").trim();

    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const parent = stack[stack.length - 1].value;
    if (rawValue === "") {
      parent[key] = {};
      stack.push({ indent, value: parent[key] });
    } else {
      parent[key] = rawValue;
    }
  }

  return root;
}

function writeConfig(config) {
  mkdirSync(".archetipo", { recursive: true });
  const yaml = `#only valid for github connector
github:
  owner: ${config.github.owner}
  project_number: ${config.github.project_number}
  project_node_id: ${config.github.project_node_id}
  fields:
    status:
      id: ${config.github.fields.status.id}
      options:
        todo: ${config.github.fields.status.options.todo}
        planned: ${config.github.fields.status.options.planned}
        in_progress: ${config.github.fields.status.options.in_progress}
        review: ${config.github.fields.status.options.review}
        done: ${config.github.fields.status.options.done}
    priority:
      id: ${config.github.fields.priority.id}
      options:
        high: ${config.github.fields.priority.options.high}
        medium: ${config.github.fields.priority.options.medium}
        low: ${config.github.fields.priority.options.low}
    story_points:
      id: ${config.github.fields.story_points.id}
    epic:
      id: ${config.github.fields.epic.id}
      # Options managed dynamically by /archetipo-spec
`;
  writeFileSync(".archetipo/config.yaml", yaml, "utf8");
}

function validateConfig(config) {
  const requiredValues = {
    "github.owner": config.github.owner,
    "github.project_number": config.github.project_number,
    "github.project_node_id": config.github.project_node_id,
    "github.fields.status.id": config.github.fields.status.id,
    "github.fields.status.options.todo": config.github.fields.status.options.todo,
    "github.fields.status.options.planned": config.github.fields.status.options.planned,
    "github.fields.status.options.in_progress": config.github.fields.status.options.in_progress,
    "github.fields.status.options.review": config.github.fields.status.options.review,
    "github.fields.status.options.done": config.github.fields.status.options.done,
    "github.fields.priority.id": config.github.fields.priority.id,
    "github.fields.priority.options.high": config.github.fields.priority.options.high,
    "github.fields.priority.options.medium": config.github.fields.priority.options.medium,
    "github.fields.priority.options.low": config.github.fields.priority.options.low,
    "github.fields.story_points.id": config.github.fields.story_points.id,
    "github.fields.epic.id": config.github.fields.epic.id,
  };
  const missing = Object.entries(requiredValues)
    .filter(([, value]) => !value)
    .map(([key]) => key);
  if (missing.length > 0) {
    fail(`Configurazione Archetipo incompleta: ${missing.join(", ")}`);
  }
}

function normalizeEpics(epics) {
  if (!Array.isArray(epics)) {
    fail("Input epics deve essere un array o contenere { epics: [...] }.");
  }
  return epics.map((epic) => ({
    code: required(epic.code || codeFromEpic(epic.name || epic.title), "epic.code"),
    title: required(epic.title || epic.name, "epic.title"),
  }));
}

function epicOptionName(epic) {
  const code = required(epic.code || codeFromEpic(epic.name || epic.title), "epic.code");
  const title = required(epic.title || epic.name, "epic.title").replace(new RegExp(`^${code}:?\\s*`), "");
  return `${code}: ${title}`;
}

function codeFromEpic(value) {
  return String(value || "").match(/EP-\d{3}/)?.[0] || "";
}

function codeFromTitle(value) {
  return String(value || "").match(/US-\d{3}/)?.[0] || "";
}

function findEpicLabel(labels) {
  return (labels || [])
    .map((label) => (typeof label === "string" ? label : label.name))
    .find((name) => /^EP-\d{3}$/.test(name));
}

function buildPlanPointer(planFile, summary, footer) {
  const total = summary.total_tasks ?? summary.tasks_total ?? "?";
  const implementation = summary.implementation_tasks ?? summary.implementation ?? "?";
  const tests = summary.test_tasks ?? summary.tests ?? "?";
  const effort = summary.effort ?? summary.total_effort ?? "?";
  return `---

## Piano di Implementazione

**File:** \`${planFile}\`

**Riepilogo:**
- Task totali: ${total} (${implementation} implementazione + ${tests} test)
- Effort stimato: ${effort}

I task sono linkati come sub-issue native (vedi sezione "Sub-issues" sopra).

${footer || "_Generato da Archetipo Planning Team_"}`;
}

function issueNumberFromText(text) {
  const match = String(text).match(/\/issues\/(\d+)|#(\d+)/);
  const number = match?.[1] || match?.[2];
  if (!number) {
    fail(`Non riesco a ricavare il numero issue da: ${text}`);
  }
  return Number(number);
}

function required(value, name) {
  if (value === undefined || value === null || value === "") {
    fail(`Valore richiesto mancante: ${name}`);
  }
  return value;
}

function requiredArray(value, name) {
  if (!Array.isArray(value) || value.length === 0) {
    fail(`Array richiesto mancante o vuoto: ${name}`);
  }
  return value;
}

function numberArg(value, fallback) {
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    fail(`Numero non valido: ${value}`);
  }
  return parsed;
}

function output(args, data, message) {
  if (args.json) {
    console.log(JSON.stringify(data, null, 2));
  } else {
    console.log(message);
  }
}

function info(message) {
  console.log(message);
}

function fail(message) {
  console.error(`Errore: ${message}`);
  process.exit(1);
}
