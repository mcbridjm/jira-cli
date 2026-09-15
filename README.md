# jira-cli.sh

A single, function-agnostic bash script for automating common Jira actions
against `https://jira.devops.va.gov` (a Jira Server/Data Center instance)
using a Personal Access Token (PAT) — without ever having to type the PAT
interactively.


## How authentication works

The script sources a `.env` file (default: same directory as the script)
containing:

```
PAT=<your Jira personal access token>
```

Copy `.env.example` to `.env` and fill in your own PAT. `.env` is
git-ignored and must never be committed.

- If `PAT` is already set in the environment, the `.env` file is skipped.
- If neither is available, the script falls back to an interactive, silent
  (`read -s`) prompt so the token is never echoed, logged, or written to
  shell history.
- The PAT is only ever sent as an `Authorization: Bearer <PAT>` HTTP header
  (this instance is Jira Server/Data Center, not Jira Cloud, so Bearer auth
  is used rather than OAuth/Basic auth or the v3 Cloud API).
- The in-memory copies of the token (`PAT` and `JIRA_PAT`) are `unset` as
  soon as they are no longer needed.
- **The `.env` file should never be committed to version control.**

## Actions

| Action        | Purpose                                                              |
|---------------|-----------------------------------------------------------------------|
| `comment`     | Add a comment to an existing issue                                   |
| `description` | Replace an existing issue's description                              |
| `transition`  | Move an issue to a new status (single workflow hop)                  |
| `create`      | Create a new issue in a project, optionally setting issue type, owner/assignee, Epic Link, and Sprint |
| `assign`      | Assign an existing issue to a user                                   |
| `mysprint`    | List issues assigned to you (the PAT owner) in any open sprint, including each issue's Sprint id/name |
| `field`       | Look up custom field ids by (partial, case-insensitive) name match   |
| `search`      | Look up issue(s) by issue key or free text and print their full content |
| `setparent`   | Set an issue's Advanced Roadmaps "Parent Link" field to nest it (e.g. an Epic) under a parent issue |
| `removelabel` | Remove a single label from an existing issue, leaving all other labels untouched |

### Usage

```bash
./jira-cli.sh comment     <ISSUE-KEY> "<comment text>"                       [env-file]
./jira-cli.sh description <ISSUE-KEY> "<description text>"                  [env-file]
./jira-cli.sh transition  <ISSUE-KEY> "<target status name>"                [env-file]
./jira-cli.sh create      <PROJECT-KEY> "<summary>" "<description>" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--epicname <name>] [--env <env-file>]
./jira-cli.sh assign      <ISSUE-KEY> <assignee-username>                   [env-file]
./jira-cli.sh mysprint    [PROJECT-KEY]                                     [env-file]
./jira-cli.sh field       <search-term>                                     [env-file]
./jira-cli.sh search      <ISSUE-KEY | "text to search">  [--project <PROJECT-KEY>] [--sprint] [--env <env-file>]
./jira-cli.sh setparent   <ISSUE-KEY> <PARENT-ISSUE-KEY>                    [env-file]
./jira-cli.sh removelabel <ISSUE-KEY> <label>                               [env-file]
```

Running the script with no arguments (or `-h`/`--help`) prints the full
usage/help text and exits without making any Jira calls.

### Examples

```bash
./jira-cli.sh comment EAWM-7384 "Applied topology spread constraints."
./jira-cli.sh description EAWM-7384 "$(cat new-description.txt)"
./jira-cli.sh transition EAWM-7384 "Resolved"
./jira-cli.sh create EAWM "Promote topology spread constraints to Production" "$(cat followup-desc.txt)" --type Story --assignee adam.schaefer2@va.gov
./jira-cli.sh create EAWM "Research OCR true-up" "$(cat desc.txt)" --epic EAWM-8837 --sprint 52476 --assignee adam.schaefer2@va.gov
./jira-cli.sh create EAWM "Cloud Spend Savings" "$(cat epic-desc.txt)" --type Epic --epicname "Cloud Spend Savings" --assignee adam.schaefer2@va.gov
./jira-cli.sh assign EAWM-7385 adam.schaefer2@va.gov
./jira-cli.sh mysprint EAWM
./jira-cli.sh field sprint
./jira-cli.sh search EAWM-8812
./jira-cli.sh search "Account Re-use" --project EAWM --sprint
./jira-cli.sh setparent EAWM-9246 EAWM-9263
./jira-cli.sh removelabel EAWM-9246 Team5
```

## How each action works

- **`comment`** — `POST /rest/api/2/issue/<key>/comment` with `{"body": "<text>"}`.
- **`description`** — `PUT /rest/api/2/issue/<key>` with `{"fields": {"description": "<text>"}}`.
- **`transition`** — Fetches `GET /rest/api/2/issue/<key>/transitions`, then
  matches the target text (case-insensitive) against either the
  transition's own name (e.g. "Start Work") or its destination status name
  (e.g. "In Work"). If found, it fires
  `POST /rest/api/2/issue/<key>/transitions` with the matched transition
  `id`. If no match exists, it prints the transitions that ARE available
  from the issue's current status and exits non-zero, rather than guessing.
  **This is deliberately single-hop only** — Jira workflows commonly
  require multiple hops (e.g. To Do → In Work → Resolved), and
  auto-chaining hops could push an issue through unintended intermediate
  statuses (each of which may fire its own notifications/side effects in
  the org's workflow). Run the command again after each hop to discover
  and execute the next one.
- **`create`** — `POST /rest/api/2/issue` with `fields.project.key`,
  `fields.issuetype.name` (default `Story`), `fields.summary`,
  `fields.description`, and optionally `fields.assignee.name` (`--assignee`),
  `customfield_10001` (`--epic`, the Epic Link field — takes the epic's
  issue key, e.g. `EAWM-8837`), `customfield_10000` (`--sprint`, the
  Sprint field — takes the sprint's **numeric id**, e.g. `52476`, not its
  display name), and `customfield_10003` (`--epicname`, the **Epic Name**
  field — required by Jira when `--type Epic` is used; ignored for other
  issue types). Jira validates the whole payload atomically, so a failed
  create (e.g. missing a required custom field) does not leave a
  partial/broken issue behind. Use `mysprint` to find the active sprint's
  id, and `field` to re-discover the Epic Link/Sprint custom field ids if
  they ever differ (e.g. on a different Jira project/instance).
- **`assign`** — `PUT /rest/api/2/issue/<key>/assignee` with
  `{"name": "<username>"}`. On this Server/Data Center instance the
  assignee value is the account's Jira **username** (here, the user's VA
  email address, e.g. `adam.schaefer2@va.gov`) — **not** a Jira Cloud
  `accountId`. Look up a username with:
  ```bash
  curl -s -H "Authorization: Bearer $PAT" \
    "https://jira.devops.va.gov/rest/api/2/user/search?username=<email>"
  ```
- **`mysprint`** — Runs a JQL search,
  `assignee = currentUser() AND sprint in openSprints()` (optionally
  prefixed with `project = <KEY> AND` when a project key is given), via
  `GET /rest/api/2/search`. `currentUser()` resolves server-side from the
  PAT's identity, so this always reports issues assigned to whoever owns
  the token — no separate username lookup is needed. For each result it
  prints the key, browse URL, issue type, status, Sprint (id/name/state,
  parsed from the raw `customfield_10000` greenhopper object string), and
  a description snippet (truncated to 300 characters).
- **`field`** — `GET /rest/api/2/field`, filtered client-side (via `jq`'s
  `test($term; "i")`) to fields whose name matches the given search term
  case-insensitively, printed as `<id>\t<name>` sorted by name. This was
  the ad hoc lookup originally used to discover the Epic Link
  (`customfield_10001`) and Sprint (`customfield_10000`) field ids for
  `create --epic`/`--sprint` — it's now a first-class action so that
  lookup is repeatable instead of a one-off throwaway script.
- **`search`** — Looks up issue(s) and prints their **full** content
  (unlike `mysprint`'s 300-character description snippet). If the query
  looks like an issue key (e.g. `EAWM-8812`), it's fetched directly via
  `GET /rest/api/2/issue/<key>`. Otherwise the query is treated as free
  text and run as a JQL `text ~ "<query>"` search via
  `GET /rest/api/2/search` (Jira's full-text search across
  summary/description/comments/etc.), optionally narrowed with
  `--project <PROJECT-KEY>` and/or `--sprint` (adds
  `AND sprint in openSprints()`, matching `mysprint`'s open-sprint
  scoping). Each result prints key, browse URL, issue type, status,
  assignee, Sprint (id/name/state), full summary/description, and any
  comments.
- **`setparent`** — `PUT /rest/api/2/issue/<key>` with
  `{"fields": {"customfield_11703": "<PARENT-ISSUE-KEY>"}}`.
  `customfield_11703` is this instance's Advanced Roadmaps "Parent Link"
  field (`com.atlassian.jpo:jpo-custom-field-parent`), which is distinct
  from Epic Link (`customfield_10001`, used to link a Story down to its
  owning Epic) — Parent Link links an issue (e.g. an Epic) *upward* to a
  parent issue, which is how multiple Epics get nested/grouped under one
  umbrella Epic in Advanced Roadmaps-style hierarchies on this instance.
- **`removelabel`** — Fetches the issue's current `labels` field via
  `GET /rest/api/2/issue/<key>?fields=labels`, removes the given label
  (case-sensitive exact match) from the list if present, and PUTs the
  resulting list back with `{"fields": {"labels": [...]}}`. All other
  labels on the issue are preserved. If the label is not present, the
  issue's labels are left unchanged and a friendly message is printed
  instead of an error, since the desired end state (label absent)
  already holds.

## Why it works this way

- **One script, multiple actions** (rather than one script per action) —
  keeps a single place for PAT loading, error handling, and HTTP
  boilerplate, and matches the "function agnostic" naming/design intent.
- **`.env`-based PAT loading** — avoids interactive prompts so the script
  can be called unattended/programmatically, while still never persisting
  the token anywhere in cleartext logs, files it creates, or shell
  history.
- **REST API v2** — this Jira instance is Server/Data Center, which uses
  `Authorization: Bearer <PAT>` and the `/rest/api/2/...` endpoints; Jira
  Cloud's v3 API and OAuth flows do not apply here.
- **No `createmeta` dependency** — `/rest/api/2/issue/createmeta` is
  blocked/disabled on this instance (returns `404 Issue Does Not Exist`
  regardless of parameters), so `create` relies on the well-known standard
  fields (`project`, `issuetype`, `summary`, `description`, `assignee`)
  plus custom field ids discovered via the `field` action (Epic Link,
  Sprint), instead of querying create metadata dynamically.
- **Single-hop transitions only** — protects against accidentally
  automating an issue through multiple unintended statuses in one call.
- **`field` as a first-class action, not a throwaway script** — every
  helper query used while building the `create --epic`/`--sprint` support
  (epic lookup, sprint field discovery, custom field id discovery) was
  folded into this one script as reusable actions/options rather than left
  as one-off files, keeping with the "one script, multiple actions"
  design intent.

## Requirements

- `bash`, `curl`, `jq`
- A `.env` file (or pre-set `PAT` environment variable) with a valid Jira
  Personal Access Token
- Network access to `https://jira.devops.va.gov`

## Related scripts

- `apply-manage-topology.sh` — applies `nodeAffinity` +
  `topologySpreadConstraints` to all `manageserverbundle` custom resources
  across an OpenShift cluster, to ensure MAS Manage pods spread evenly
  across availability zones/nodes. The Jira automation in this script was
  built to document and track that work (see EAWM-7384 and EAWM-9125).
