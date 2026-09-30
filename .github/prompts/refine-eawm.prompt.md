---
description: "Refine an EAWM Jira story: evaluate it against the team's refinement standard and recommend changes (no edits without approval)."
argument-hint: "EAWM issue key, e.g. EAWM-9295"
---
# Refine EAWM Jira story

Refine the EAWM Jira issue given by the user (e.g. `EAWM-9295`).

## Process
1. Fetch the issue read-only with `./jira-cli.sh search <KEY>` (Git Bash; see repo notes). Also read any fields below that `search` does not show.
2. Evaluate every item in the **Refinement standard** and report each as OK / GAP / MISSING, with the current value.
3. Draft recommended text for every GAP or MISSING item, ready to paste into Jira.
4. Flag inconsistencies (see **Consistency checks**).
5. **Recommend only.** Make no Jira edits (fields, comments, transitions) until the user explicitly approves the exact change.

## Refinement standard
| # | Item | Jira field | Rule |
|---|------|-----------|------|
| 1 | Title | `summary` | Concise summary of the issue. |
| 2 | Priority | `priority` | One of **Blocker, Critical, High, Medium, Low**. Justify the recommendation. |
| 3 | Description | `description` | Opens with *As a* [role of user] *I want to* [perform a task (goal)] *So that* [achieve a benefit]. |
| 4 | Evaluation | `description` | Placed directly **after** the As a / I want to / So that statement. See **Evaluation**. |
| 5 | Acceptance criteria | Acceptance Criteria (`customfield_10500`) | Defines done. Use **GIVEN** [how things begin] **WHEN** [action is taken] **THEN** [outcome] whenever possible. A checklist is acceptable when the story is better suited to a list (e.g. operational/infrastructure steps). |
| 6 | Feature type | Feature Type (`customfield_23300`) | One of **Feature, Enabler, Spike, None**. Feature = solution-focused, delivers user/business value. Enabler = implementation-focused (architecture, infra, refactoring, foundation work) with no direct user-visible value. Spike = timeboxed investigation that produces learning, not a deliverable. None = doesn't meaningfully fit the above, or team doesn't need to classify it. |
| 7 | Request type | Request Type (`customfield_16455`) | One of **Development, Enhancement, Modernization, Research, Sustainment, Technical Debt, Other**. See **Request type reference** below for definitions and default priority guidance; use `Other` plus a triage owner if genuinely unclear. Note: this project does not use Change Request Type (`customfield_14601`) or the other similarly-named `customfield_17610` "Request Type" field — both are unused/legacy on this instance. |
| 8 | Common fields | `component`, `labels`, `assignee`, `customfield_22701` (Collaborators), Sprint, Story Points, Epic Link | Every issue should have these set for triage per team standard, in addition to Summary/Priority/Description covered above. |

## Evaluation
Add to the description after the user story, as three sections, each with a **Low / Medium / High** recommendation and a short justification:
- **Complexity**: technical difficulty and unknowns in resolving the issue.
- **Volume of steps**: the number of discrete steps to resolve the issue (list them).
- **Risk**: what could go wrong, likelihood/impact, mitigation, and rollback.

This evaluation informs the team when estimating Story Points (`customfield_10100`). Do not set Story Points or use Risk Category.

## Priority reference
(from EAWM Agile Fundamentals) Use these to justify the recommendation, not just pick a label:
- **Blocker**: completely blocks progress (broken dependency, critical bug preventing a feature from working, missing resources/info to proceed).
- **Critical**: extremely urgent, must be addressed immediately (key function OFFLINE, security vulnerability, complete system failure, essential feature down).
- **High**: significant impact, should be addressed ASAP but not blocking (major data loss/corruption, performance issue affecting many users, a feature critical to overall functionality).
- **Medium**: some impact, normal workflow (minor inconvenience, nice-to-have feature, performance issue affecting few users).
- **Low**: little impact, can wait for downtime/larger refactor (cosmetic issues, non-essential features).
- **Unassigned**: not yet evaluated/prioritized by the team or PO.

## Request type reference
(from EAWM Agile Fundamentals) Each entry: definition / when to use / default priority.
- **Development**: build new user-facing functionality or backend features. Medium -> High.
- **Enhancement**: improve existing functionality (UX, performance, config, small behavior changes), not a full new feature. Medium (High if addressing known pain).
- **Modernization**: upgrade/replace underlying tech, platform, or architecture. Medium -> High.
- **Research**: timeboxed spike to reduce risk/uncertainty. Low -> Medium (raise if blocking other work).
- **Sustainment**: routine operational work — maintenance, monitoring, SLA-driven tasks, incident follow-ups. Medium (Critical for incidents).
- **Technical Debt**: pay down code/design/process debt without changing behavior. Low -> High depending on impact on velocity/quality.
- **Other/None**: non-technical or unclassified; needs a triage owner. Unassigned until triaged.

## Definition of Done
A fully refined/closeable issue should satisfy: accepted into the sprint, refined, tested, demonstrable at Sprint Review, and closed. Use this to sanity-check Status/Resolution/Story State together, not just each field alone.

## Consistency checks
Also flag (do not fix without approval):
- Status/Resolution vs evidence (e.g. Resolved/Done with acceptance criteria not shown as met, no linked PR, empty test evidence) — see **Definition of Done**.
- Resolution Description (`customfield_13214`) contradicting Resolution.
- Story State (`customfield_11700`) out of step with Status.
- Missing Epic Link (`customfield_10001`), Sprint, Assignee, Collaborators, Component, Labels, Story Points, Due Date, Fix Version, or Links where expected.
- Acceptance criteria that is a placeholder/prompt question rather than real, demonstrable criteria (e.g. "How would you demonstrate this during sprint review?" left unanswered).
- Duplicate or conflicting content (e.g. two different step lists in the description).
- Request Type inconsistent with the described work (e.g. a production defect fix filed as "Enhancement" instead of "Sustainment" — see **Request type reference**).
- Request Type set on the wrong custom field — this project uses `customfield_16455` ("Request Type"); ignore/do not set `customfield_14601` ("Change Request Type") or `customfield_17610` (also named "Request Type", unused).

## Output format
1. Snapshot table of the issue's key fields.
2. Refinement scorecard (items 1–7: OK / GAP / MISSING + current value).
3. Recommended text for each gap.
4. Consistency findings.
5. Ask which recommendations to apply.
