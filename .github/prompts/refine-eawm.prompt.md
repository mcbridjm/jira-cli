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
| 6 | Feature type | Feature Type (`customfield_23300`) | One of **Enabler, Feature, Spike**. |
| 7 | Request type | Change Request Type (`customfield_14601`) | One of **Development, Enhancement, Modernization, Research, Sustainment, Technical Debt, Other/None**. |

## Evaluation
Add to the description after the user story, as three sections, each with a **Low / Medium / High** recommendation and a short justification:
- **Complexity**: technical difficulty and unknowns in resolving the issue.
- **Volume of steps**: the number of discrete steps to resolve the issue (list them).
- **Risk**: what could go wrong, likelihood/impact, mitigation, and rollback.

This evaluation informs the team when estimating Story Points (`customfield_10100`). Do not set Story Points or use Risk Category.

## Consistency checks
Also flag (do not fix without approval):
- Status/Resolution vs evidence (e.g. Resolved/Done with acceptance criteria not shown as met, no linked PR, empty test evidence).
- Resolution Description (`customfield_13214`) contradicting Resolution.
- Story State (`customfield_11700`) out of step with Status.
- Missing Epic Link (`customfield_10001`), Sprint, Assignee, Due Date, Fix Version, or Links where expected.
- Duplicate or conflicting content (e.g. two different step lists in the description).

## Output format
1. Snapshot table of the issue's key fields.
2. Refinement scorecard (items 1–7: OK / GAP / MISSING + current value).
3. Recommended text for each gap.
4. Consistency findings.
5. Ask which recommendations to apply.
