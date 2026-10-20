#!/usr/bin/env bash
#
# jira-cli.sh
#
# Updates or creates Jira issues via the REST API using a Personal Access
# Token (PAT). The token is loaded from a local .env file (variable PAT)
# rather than typed interactively, so this can be run non-interactively.
# If PAT is not already set in the environment and no .env is found, it
# falls back to an interactive silent prompt.
#
# Actions:
#   comment     - add a comment to an existing issue
#   description - replace an existing issue's description
#   summary     - replace an existing issue's summary/title
#   transition  - move an existing issue to a new status (single workflow
#                 hop only - see notes below for multi-step workflows)
#   create      - create a new issue in a project, optionally setting its
#                 issue type, owner/assignee, Epic Link, Sprint, labels,
#                 and component
#   assign      - assign an existing issue to a user (by Jira username)
#   link        - link two existing issues together (default link type
#                 "Relates"), e.g. to connect a new story to prior related
#                 stories
#   mysprint    - list issues assigned to the PAT owner in any open sprint
#                 (optionally scoped to one project), printing key, URL,
#                 status, issue type, description, and Sprint (id/name) for
#                 each - use this to find the numeric sprint id for
#                 create's --sprint option
#   field       - look up custom field ids by (partial, case-insensitive)
#                 name match, e.g. to (re)discover the Epic Link / Sprint
#                 field ids on this Jira instance
#   search      - look up issue(s) by issue key OR free-text search, and
#                 print the FULL content (summary, type, feature/request
#                 type, status, resolution, story state, priority,
#                 assignee, sprint, epic, labels, components, fix version,
#                 story points, due/target dates, full description,
#                 acceptance criteria, links, comments) of each match -
#                 optionally scoped to a project and/or the open sprint
#   recentactivity - list issues owned by (assigned to) a given user
#                 (default: the PAT owner, or a specific Jira username via
#                 --user) where that same user changed the status within
#                 the last N days (default 7), optionally scoped to one
#                 project - prints key, URL, full description, and the
#                 most recent status transition (from/to + date) made by
#                 that user, for building status-report summaries
#   futureactivity - the forward-looking counterpart to recentactivity:
#                 list issues owned by (assigned to) a given user (default:
#                 the PAT owner, or a specific Jira username via --user)
#                 that are in an open sprint and not yet in a "Done"-type
#                 status - i.e. remaining/upcoming work for that user in
#                 the current sprint - optionally scoped to one project
#   duesoon     - list issues with a given label whose due date falls
#                 within the next N days (default 30), optionally scoped
#                 to one project - a planning report independent of
#                 assignee/sprint, e.g. for label-based (team/category)
#                 lookahead rather than per-person status reporting
#   setparent   - set an issue's Advanced Roadmaps "Parent Link" field
#                 (customfield_11703) to another issue's key - used to
#                 nest one Epic under a higher-level parent Epic/Initiative
#                 (this is separate from Epic Link, which links a Story to
#                 its owning Epic; Parent Link links an Epic upward to a
#                 parent issue in the Advanced Roadmaps hierarchy)
#   removelabel - remove a single label from an existing issue's labels
#                 field, leaving all other labels on the issue untouched
#   refine      - read-only scorecard of one issue against the EAWM
#                 refinement standard (.github/prompts/refine-eawm.prompt.md),
#                 flagging each item OK / GAP / MISSING plus consistency
#                 WARNings (e.g. "Feature type: MISSING")
#   scorecard   - read-only monthly "EAWM Product Scorecard" (lead/cycle
#                 time, releases, defect severity counts, red zone risks,
#                 backlog/release throughput), printed as a table and
#                 optionally appended to a CSV file
#   sprintreview - read-only end-of-sprint carryover review: every
#                 not-Done issue in one sprint, grouped by swimlane, with
#                 days in status, other sprints, blockers, last comment,
#                 and whether the assignee left a rollover comment
#   setcomponent - set an existing issue's components field to a single
#                 named component (replacing any existing components),
#                 resolving the component name to its id via the
#                 project's components endpoint first
#   dates       - print status, resolution date, and per-comment author
#                 + timestamp for one or more issues (useful for citing
#                 when an issue was evaluated/completed, since 'search'
#                 does not surface comment/resolution timestamps)
#
# Usage:
#   ./jira-cli.sh comment     <ISSUE-KEY> "<comment text>"          [env-file]
#   ./jira-cli.sh description <ISSUE-KEY> "<description text>"     [env-file]
#   ./jira-cli.sh summary     <ISSUE-KEY> "<new summary/title>"     [env-file]
#   ./jira-cli.sh transition  <ISSUE-KEY> "<target status name>"   [env-file]
#   ./jira-cli.sh create      <PROJECT-KEY> "<summary>" "<description>" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--labels <label1,label2>] [--component <name>] [--epicname <name>] [--env <env-file>]
#   ./jira-cli.sh assign      <ISSUE-KEY> <assignee-username>       [env-file]
#   ./jira-cli.sh link        <ISSUE-KEY> <TARGET-ISSUE-KEY> [--type <link-type>] [--env <env-file>]
#   ./jira-cli.sh mysprint    [PROJECT-KEY] [env-file]
#   ./jira-cli.sh field       <search-term> [env-file]
#   ./jira-cli.sh search      <ISSUE-KEY | "text to search">  [--project <PROJECT-KEY>] [--sprint] [--env <env-file>]
#   ./jira-cli.sh recentactivity [--days <n>] [--project <PROJECT-KEY>] [--user <jira-username>] [--env <env-file>]
#   ./jira-cli.sh futureactivity [--project <PROJECT-KEY>] [--user <jira-username>] [--env <env-file>]
#   ./jira-cli.sh duesoon      <LABEL> [--project <PROJECT-KEY>] [--days <n>] [--env <env-file>]
#   ./jira-cli.sh setparent   <ISSUE-KEY> <PARENT-ISSUE-KEY>        [env-file]
#   ./jira-cli.sh removelabel <ISSUE-KEY> <label>                   [env-file]
#   ./jira-cli.sh refine      <ISSUE-KEY>                           [env-file]
#   ./jira-cli.sh scorecard   [--month YYYY-MM] [--project <PROJECT-KEY>] [--csv <file>] [--env <env-file>]
#   ./jira-cli.sh sprintreview <SPRINT-ID> [--project <PROJECT-KEY>] [--since YYYY-MM-DD] [--csv <file>] [--env <env-file>]
#   ./jira-cli.sh setcomponent <ISSUE-KEY> <component-name>         [env-file]
#   ./jira-cli.sh dates       <ISSUE-KEY> [ISSUE-KEY...]            [--env <env-file>]
#
# Examples:
#   ./jira-cli.sh comment EAWM-7384 "Applied topology spread constraints."
#   ./jira-cli.sh description EAWM-7384 "$(cat new-description.txt)"
#   ./jira-cli.sh transition EAWM-7384 "Resolved"
#   ./jira-cli.sh create EAWM "Promote topology spread constraints to Production" "$(cat followup-desc.txt)" --type Story --assignee adam.schaefer2@va.gov
#   ./jira-cli.sh create EAWM "Research OCR true-up" "$(cat desc.txt)" --epic EAWM-8837 --sprint 52476 --assignee adam.schaefer2@va.gov
#   ./jira-cli.sh create EAWM "WASA support" "$(cat desc.txt)" --labels Infrastructure,WASA --assignee adam.schaefer2@va.gov
#   ./jira-cli.sh assign EAWM-7385 adam.schaefer2@va.gov
#   ./jira-cli.sh link EAWM-9200 EAWM-5833 --type Relates
#   ./jira-cli.sh mysprint EAWM
#   ./jira-cli.sh field sprint
#   ./jira-cli.sh search EAWM-8812
#   ./jira-cli.sh search "Account Re-use" --project EAWM --sprint
#   ./jira-cli.sh recentactivity
#   ./jira-cli.sh recentactivity --days 14 --project EAWM
#   ./jira-cli.sh recentactivity --user macklin.mcbride@va.gov --days 7
#   ./jira-cli.sh futureactivity
#   ./jira-cli.sh futureactivity --user macklin.mcbride@va.gov --project EAWM
#   ./jira-cli.sh duesoon Infrastructure --project EAWM --days 30
#   ./jira-cli.sh refine EAWM-9295
#   ./jira-cli.sh scorecard --month 2026-09 --csv eawm-scorecard.csv
#   ./jira-cli.sh sprintreview 52479 --project EAWM --csv sp7-review.csv
#
# Notes on 'assign' / create's --assignee (the issue "owner"):
#   The assignee value must be the Jira account's "name" (username), which
#   on this Server/Data Center instance is the user's login (often their
#   email address, e.g. mcbridjm@us.ibm.com) - NOT a Cloud accountId.
#   You can look it up with:
#     curl -s -H "Authorization: Bearer $PAT" \
#       "${JIRA_BASE_URL}/rest/api/2/user/search?username=<email>"
#
# Notes on create's --epic / --sprint:
#   These map to custom fields on IBM Jira (https://jsw.ibm.com):
#   Epic Link = customfield_10100 (or customfield_10001), Sprint = customfield_10104 (or customfield_10000).
#   Run `./jira-cli.sh mysprint <PROJECT-KEY>` to see the active sprint's id/name.
#
# Notes on 'search':
#   If the query looks like an issue key (e.g. EAWM-8812 - letters, a dash,
#   digits), it is fetched directly via GET /rest/api/2/issue/<key> and its
#   full content is printed. Otherwise the query is treated as free text
#   and run as a JQL `text ~ "<query>"` search (Jira's full-text search
#   across summary/description/comments/etc.), optionally narrowed with
#   `--project <PROJECT-KEY>` and/or `--sprint` (adds
#   `AND sprint in openSprints()`, matching the same open-sprint scoping
#   used by 'mysprint'). Unlike 'mysprint', which truncates descriptions to
#   300 characters for a quick scan, 'search' prints each match's FULL
#   description (and top-level comments) since the point is to retrieve
#   complete issue content, not a summary list.
#
# Notes on 'refine':
#   Fetches one issue and checks: Title; Priority in Blocker/Critical/
#   High/Medium/Low; description contains As a / I want to / So that;
#   description has Complexity, Volume and Risk evaluations each rated
#   Low/Medium/High and placed after the user story; Acceptance Criteria
#   (customfield_10500) present (GIVEN/WHEN/THEN preferred, checklist
#   allowed); Feature Type (customfield_23300) in Feature/Enabler/Spike/
#   None; Request Type (customfield_16455) in Development/Enhancement/
#   Modernization/Research/Sustainment/Technical Debt/Other. (This project
#   does not use the similarly-named customfield_14601 "Change Request
#   Type" or customfield_17610 "Request Type" fields.)
#   Consistency WARNings: resolved with no linked PR (from the Development
#   field customfield_10006), Resolution Description set on a resolved
#   issue, Story State (customfield_11700) "Draft" on a resolved issue,
#   and missing Epic Link / Sprint / Assignee / Due Date / Fix Version.
#   Text checks are heuristics - review the output, don't treat it as final.
#
# Notes on 'transition':
#   Jira workflows often require multiple hops (e.g. To Do -> In Work ->
#   Resolved) - a single call can only perform whatever transition is
#   directly available from the issue's CURRENT status. This action looks
#   for a transition whose name OR destination status matches the target
#   (case-insensitive). If no direct hop exists, it prints the available
#   transitions from the current status so you know what to run next, and
#   exits non-zero without changing anything.
#
# Notes on 'recentactivity':
#   Runs the JQL `assignee = <user> AND status changed by <user> after
#   -<N>d` (default N=7, optionally narrowed with `--project
#   <PROJECT-KEY>`) with
#   `expand=changelog` to fetch each matching issue's full changelog. By
#   default <user> is `currentUser()` (the PAT owner, identified via GET
#   /rest/api/2/myself); pass `--user <jira-username>` to report on any
#   other Jira user's status changes instead (their Jira "name"/login,
#   e.g. an email address on this instance - see the assign/--assignee
#   notes above for how to look that up). For each issue, the changelog is
#   scanned for 'status' field history entries authored by that user whose
#   timestamp falls within the last N days; the most recent such entry's
#   from/to status and date are printed alongside the key, URL, and full
#   description - the from/to + date are what changed, the description is
#   the raw material for writing a synopsis.
#
# Notes on 'futureactivity':
#   Runs the JQL `assignee = <user> AND sprint in openSprints() AND
#   statusCategory != Done` (optionally narrowed with `--project
#   <PROJECT-KEY>`), where <user> defaults to `currentUser()` (the PAT
#   owner) or a specific Jira username via `--user`. This is the mirror
#   image of 'recentactivity': instead of looking backward at status
#   changes already made, it looks forward at everything that user still
#   owns and hasn't finished in the currently open sprint(s), regardless
#   of who last changed its status - useful for previewing what's still
#   ahead before it shows up in a future recentactivity report. No
#   changelog is needed since past status changes aren't relevant here.
#
# Notes on 'duesoon':
#   Runs the JQL `labels = <LABEL> AND duedate >= 0d AND duedate <=
#   <N>d` (default N=30, optionally narrowed with `--project
#   <PROJECT-KEY>`), ordered by due date ascending. Unlike
#   recentactivity/futureactivity, this is not scoped to any particular
#   assignee - it's a label-based planning report (e.g. "everything
#   labeled Infrastructure due in the next 30 days") that prints key,
#   URL, due date, assignee, and full description for each match. Jira's
#   `duedate` field must actually be set on an issue for it to appear
#   here; on this instance, EAWM-8762 is an example of an issue with both
#   a duedate and the Infrastructure label set.
#
# Notes on 'setparent':
#   Sets customfield_11703 ("Parent Link", the Advanced Roadmaps field
#   com.atlassian.jpo:jpo-custom-field-parent on this instance) on an
#   existing issue to point at another issue's key, e.g. to nest an Epic
#   under a higher-level parent Epic/Initiative. This is distinct from
#   Epic Link (customfield_10001), which links a Story down to its owning
#   Epic - Parent Link links an Epic upward to its parent in the
#   Advanced Roadmaps hierarchy. The field accepts a plain issue key
#   string as its value.
#
# Notes on 'removelabel':
#   Fetches the issue's current `labels` field via GET
#   /rest/api/2/issue/<key>, removes the given label (case-sensitive
#   exact match) from the list if present, and PUTs the resulting list
#   back with `{"fields": {"labels": [...]}}`. All other labels on the
#   issue are preserved. If the label is not present, the issue's labels
#   are left unchanged (a no-op PUT) and a message is printed rather than
#   erroring, since the desired end state (label absent) already holds.
#
# The .env file (default: ./.env, next to this script) must define:
#   PAT=<your jira personal access token>
#
# Notes on create's --labels:
#   Comma-separated list of labels to set on the new issue (e.g.
#   "Infrastructure,WASA"). Labels must not contain spaces (Jira label
#   convention); this is passed through as-is to the `labels` field.
#
# Notes on create's --component:
#   Sets the standard `components` field to a single existing project
#   component by name (e.g. "FY27Q1"). The name must exactly match a
#   component already defined on the target project
#   (GET /rest/api/2/project/<KEY>/components lists them) - Jira rejects
#   unknown component names.
#
# Notes on 'link':
#   Creates a Jira issue link between two existing issues via POST
#   /rest/api/2/issueLink. Defaults to link type "Relates" if --type is
#   not given; the type name must match an existing Jira link type on
#   this instance exactly (case-sensitive), e.g. "Relates", "Blocks",
#   "Duplicate".
#
# Notes on 'scorecard':
#   Period is one calendar month (--month, default = last full month).
#   Defects = issuetype Bug. Stories = issuetype Story.
#   Lead Time  = created -> first Resolved/Closed (earliest of the first
#                status change to Resolved/Closed and resolutiondate), for
#                Stories/Bugs whose end date falls in the month and that
#                are still Done. Overall = all Stories+Bugs pooled.
#   Cycle Time = first move to In Work/In Progress/Peer Review/In Test ->
#                same end date; issues that skipped those are excluded.
#   Releases   = project Fix Versions with released=true and releaseDate
#                in the month (all versions, monthly R* and ad hoc).
#   Release Cadence = avg days between each in-month release and the
#                released version before it.
#   Failed Releases = not tracked in Jira; always N/A (enter manually).
#   Sev 1-4    = Bugs created in the month by Priority: Blocker/Critical=1,
#                High=2, Medium=3, Low=4 (Prod and Non-Prod combined).
#   Red Zone Risks = open (not Done) Risks whose Residual risk
#                (customfield_16486, else Inherent risk customfield_16485)
#                is High, as of the run date.
#   Stories Added to Backlog = Stories created in the month.
#   Stories/Defect Fixes Released = Done Stories/Bugs whose Fix Version
#                is one of the month's releases.
#   The JQL behind each count is printed so it can be checked in Jira.
#
# Notes on 'sprintreview':
#   JQL: project = P AND sprint = <ID> AND statusCategory != Done AND
#   issuetype not in subTaskIssueTypes(). Swimlane is derived from the
#   status name: Planned / Not Started, Sprint TO-DO, In Progress (In
#   Work/In Progress/Peer Review/In Test), else Other (not Done).
#   "Rollover note" = YES only if a comment by the ASSIGNEE, dated on/after
#   --since (default: the sprint's start date), mentions rollover/carry
#   over/next sprint/FY27Q1/SP1/moved to. Issues in the first three lanes
#   without one are listed under NEEDS COMMENT. Nothing is written to Jira.
#

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <comment|description|summary|transition|create|assign|link|mysprint|field|search|recentactivity|futureactivity|duesoon|setparent|removelabel|setcomponent|dates|refine|scorecard|sprintreview> ..." >&2
  echo "Run with -h for full usage." >&2
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed -e 's/^# \{0,1\}//'
  exit 0
fi

ACTION="$1"
shift
JIRA_BASE_URL="${JIRA_BASE_URL:-https://jsw.ibm.com}"
# Fields shown by 'search' and checked by 'refine'.
DETAIL_FIELDS="summary,status,issuetype,priority,assignee,description,comment,customfield_10104,customfield_10000,customfield_10200,customfield_10500,customfield_32301,customfield_23300,customfield_18400,customfield_16455,labels,components,fixVersions,customfield_10106,customfield_10100,duedate,customfield_11602,customfield_11704,customfield_11603,customfield_11705,customfield_10102,customfield_10003,customfield_10001,issuelinks,resolution,customfield_13214,customfield_11700"

case "$ACTION" in
  comment|description|transition|summary)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 $ACTION <ISSUE-KEY> \"<text>\" [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    TEXT="$2"
    ENV_FILE="${3:-$(dirname "$0")/.env}"
    ;;
  create)
    if [[ $# -lt 3 ]]; then
      echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--labels <label1,label2>] [--component <name>] [--epicname <name>] [--env <env-file>]" >&2
      exit 1
    fi
    PROJECT_KEY="$1"
    SUMMARY="$2"
    DESCRIPTION="$3"
    shift 3
    ISSUETYPE="Story"
    ASSIGNEE=""
    EPIC_LINK=""
    SPRINT_ID=""
    LABELS=""
    COMPONENT=""
    EPIC_NAME=""
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)      ISSUETYPE="$2"; shift 2 ;;
        --assignee)  ASSIGNEE="$2"; shift 2 ;;
        --epic)      EPIC_LINK="$2"; shift 2 ;;
        --sprint)    SPRINT_ID="$2"; shift 2 ;;
        --labels)    LABELS="$2"; shift 2 ;;
        --component) COMPONENT="$2"; shift 2 ;;
        --epicname)  EPIC_NAME="$2"; shift 2 ;;
        --env)       ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized create option '$1'" >&2
          echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--labels <label1,label2>] [--component <name>] [--epicname <name>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  assign)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 assign <ISSUE-KEY> <assignee-username> [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    ASSIGNEE="$2"
    ENV_FILE="${3:-$(dirname "$0")/.env}"
    ;;
  link)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 link <ISSUE-KEY> <TARGET-ISSUE-KEY> [--type <link-type>] [--env <env-file>]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    TARGET_KEY="$2"
    shift 2
    LINK_TYPE="Relates"
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type) LINK_TYPE="$2"; shift 2 ;;
        --env)  ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized link option '$1'" >&2
          echo "Usage: $0 link <ISSUE-KEY> <TARGET-ISSUE-KEY> [--type <link-type>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  mysprint)
    # Both args are optional: a bare project key (no '/', no '.env' suffix)
    # is treated as PROJECT_KEY, otherwise as ENV_FILE.
    MYSPRINT_PROJECT=""
    ENV_FILE="$(dirname "$0")/.env"
    for arg in "$@"; do
      if [[ "$arg" == *.env || "$arg" == */* ]]; then
        ENV_FILE="$arg"
      else
        MYSPRINT_PROJECT="$arg"
      fi
    done
    ;;
  field)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 field <search-term> [env-file]" >&2
      exit 1
    fi
    FIELD_SEARCH="$1"
    ENV_FILE="${2:-$(dirname "$0")/.env}"
    ;;
  search)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 search <ISSUE-KEY | \"text to search\"> [--project <PROJECT-KEY>] [--sprint] [--env <env-file>]" >&2
      exit 1
    fi
    SEARCH_QUERY="$1"
    shift
    SEARCH_PROJECT=""
    SEARCH_SPRINT_ONLY=0
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) SEARCH_PROJECT="$2"; shift 2 ;;
        --sprint)  SEARCH_SPRINT_ONLY=1; shift ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized search option '$1'" >&2
          echo "Usage: $0 search <ISSUE-KEY | \"text to search\"> [--project <PROJECT-KEY>] [--sprint] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  recentactivity)
    RECENT_DAYS=7
    RECENT_PROJECT=""
    RECENT_USER=""
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --days)    RECENT_DAYS="$2"; shift 2 ;;
        --project) RECENT_PROJECT="$2"; shift 2 ;;
        --user)    RECENT_USER="$2"; shift 2 ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized recentactivity option '$1'" >&2
          echo "Usage: $0 recentactivity [--days <n>] [--project <PROJECT-KEY>] [--user <jira-username>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  futureactivity)
    FUTURE_PROJECT=""
    FUTURE_USER=""
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) FUTURE_PROJECT="$2"; shift 2 ;;
        --user)    FUTURE_USER="$2"; shift 2 ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized futureactivity option '$1'" >&2
          echo "Usage: $0 futureactivity [--project <PROJECT-KEY>] [--user <jira-username>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  duesoon)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 duesoon <LABEL> [--project <PROJECT-KEY>] [--days <n>] [--env <env-file>]" >&2
      exit 1
    fi
    DUESOON_LABEL="$1"
    shift
    DUESOON_PROJECT=""
    DUESOON_DAYS=30
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) DUESOON_PROJECT="$2"; shift 2 ;;
        --days)    DUESOON_DAYS="$2"; shift 2 ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized duesoon option '$1'" >&2
          echo "Usage: $0 duesoon <LABEL> [--project <PROJECT-KEY>] [--days <n>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  setparent)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 setparent <ISSUE-KEY> <PARENT-ISSUE-KEY> [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    PARENT_KEY="$2"
    ENV_FILE="${3:-$(dirname "$0")/.env}"
    ;;
  removelabel)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 removelabel <ISSUE-KEY> <label> [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    REMOVE_LABEL="$2"
    ENV_FILE="${3:-$(dirname "$0")/.env}"
    ;;
  refine)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 refine <ISSUE-KEY> [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    ENV_FILE="${2:-$(dirname "$0")/.env}"
    ;;
  scorecard)
    SC_MONTH="$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m)"
    SC_PROJECT="EAWM"
    SC_CSV=""
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --month)   SC_MONTH="$2"; shift 2 ;;
        --project) SC_PROJECT="$2"; shift 2 ;;
        --csv)     SC_CSV="$2"; shift 2 ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized scorecard option '$1'" >&2
          echo "Usage: $0 scorecard [--month YYYY-MM] [--project <PROJECT-KEY>] [--csv <file>] [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    # Both values are interpolated into JQL, so restrict them strictly.
    if [[ ! "$SC_MONTH" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
      echo "ERROR: --month must be YYYY-MM (got '$SC_MONTH')" >&2
      exit 1
    fi
    if [[ ! "$SC_PROJECT" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
      echo "ERROR: --project must be a Jira project key (got '$SC_PROJECT')" >&2
      exit 1
    fi
    ;;
  sprintreview)
    SR_USAGE="Usage: $0 sprintreview <SPRINT-ID> [--project <PROJECT-KEY>] [--since YYYY-MM-DD] [--csv <file>] [--env <env-file>]"
    if [[ $# -lt 1 ]]; then
      echo "$SR_USAGE" >&2
      exit 1
    fi
    SR_SPRINT="$1"
    shift
    SR_PROJECT="EAWM"
    SR_SINCE=""
    SR_CSV=""
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) SR_PROJECT="$2"; shift 2 ;;
        --since)   SR_SINCE="$2"; shift 2 ;;
        --csv)     SR_CSV="$2"; shift 2 ;;
        --env)     ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized sprintreview option '$1'" >&2
          echo "$SR_USAGE" >&2
          exit 1
          ;;
      esac
    done
    # Sprint id and project are interpolated into JQL, so restrict them strictly.
    if [[ ! "$SR_SPRINT" =~ ^[0-9]+$ ]]; then
      echo "ERROR: <SPRINT-ID> must be a numeric sprint id (got '$SR_SPRINT')" >&2
      exit 1
    fi
    if [[ ! "$SR_PROJECT" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
      echo "ERROR: --project must be a Jira project key (got '$SR_PROJECT')" >&2
      exit 1
    fi
    if [[ -n "$SR_SINCE" && ! "$SR_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "ERROR: --since must be YYYY-MM-DD (got '$SR_SINCE')" >&2
      exit 1
    fi
    ;;
  setcomponent)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 setcomponent <ISSUE-KEY> <component-name> [env-file]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    SET_COMPONENT="$2"
    ENV_FILE="${3:-$(dirname "$0")/.env}"
    ;;
  dates)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 dates <ISSUE-KEY> [ISSUE-KEY...] [--env <env-file>]" >&2
      exit 1
    fi
    DATES_KEYS=()
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --env) ENV_FILE="$2"; shift 2 ;;
        *) DATES_KEYS+=("$1"); shift ;;
      esac
    done
    ;;
  *)
    echo "ERROR: action must be one of comment, description, summary, transition, create, assign, link, mysprint, field, search, recentactivity, futureactivity, duesoon, setparent, removelabel, setcomponent, dates, refine, scorecard, sprintreview (got '$ACTION')" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 1; }

# Load PAT from .env if not already present in the environment. set -a
# auto-exports sourced assignments; only the single PAT variable is kept.
if [[ -z "${PAT:-}" && -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

JIRA_BASE_URL="${JIRA_BASE_URL:-https://jsw.ibm.com}"
JIRA_BASE_URL="${JIRA_BASE_URL%/}"

if [[ -n "${PAT:-}" ]]; then
  JIRA_PAT="$PAT"
else
  # Fallback: read silently (-s suppresses echo) so the token is never
  # printed, stored in a file, or left in shell history.
  read -rsp "Enter your Jira PAT: " JIRA_PAT
  echo
fi

# Clear PAT (the .env-sourced copy) from memory once JIRA_PAT is set; it is
# no longer needed after this point.
unset PAT

# 'mysprint' and 'field' are read-only reports with their own
# request/output shapes, so they are handled separately from the generic
# write-action flow below.
if [[ "$ACTION" == "mysprint" ]]; then
  JQL="assignee = currentUser() AND sprint in openSprints()"
  if [[ -n "$MYSPRINT_PROJECT" ]]; then
    JQL="project = ${MYSPRINT_PROJECT} AND ${JQL}"
  fi

  ENCODED_JQL=$(jq -rn --arg jql "$JQL" '$jql|@uri')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,issuetype,description,customfield_10104,customfield_10000")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  COUNT=$(jq -r '.total' <<<"$RESPONSE_BODY")
  if [[ "$COUNT" == "0" ]]; then
    echo "No issues assigned to you in an open sprint${MYSPRINT_PROJECT:+ for project $MYSPRINT_PROJECT}."
    exit 0
  fi

  # customfield_10000 (Sprint) values come back as greenhopper Sprint
  # object toString()s, e.g. "...,id=52476,...,name=EAWM FY26Q4-SP4
  # (8/12-8/25),...,state=ACTIVE,...]" - pull out id/name/state with a
  # small regex rather than parsing it as JSON.
  jq -r --arg base "$JIRA_BASE_URL" '
    .issues[] |
    "Key:         \(.key)\n" +
    "URL:         \($base)/browse/\(.key)\n" +
    "Type:        \(.fields.issuetype.name)\n" +
    "Status:      \(.fields.status.name)\n" +
    "Sprint:      \((.fields.customfield_10104 // .fields.customfield_10000 // ["(none)"])[-1])\n" +
    "Summary:     \(.fields.summary)\n" +
    "Description: \((.fields.description // "(none)") | if length > 300 then .[0:300] + "..." else . end)\n" +
    "----------------------------------------"
  ' <<<"$RESPONSE_BODY" | sed -E 's/^Sprint:.*id=([0-9]+),.*name=([^,]+),.*state=([A-Z]+).*$/Sprint:      id=\1 name=\2 state=\3/'
  exit 0
fi

if [[ "$ACTION" == "field" ]]; then
  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/field")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  MATCHES=$(jq -r --arg term "$FIELD_SEARCH" \
    '.[] | select(.name | test($term; "i")) | "\(.id)\t\(.name)"' <<<"$RESPONSE_BODY")

  if [[ -z "$MATCHES" ]]; then
    echo "No fields found matching '${FIELD_SEARCH}'."
    exit 0
  fi

  echo "$MATCHES" | sort -t$'\t' -k2
  exit 0
fi

# Prints a JSON map {"EPIC-KEY": "Epic Name"} for the Epic Links in the given issues array.
fetch_epic_names() {
  local map='{}' k name
  for k in $(jq -r '[.[].fields | (.customfield_10100 // .customfield_10001 // empty)] | unique | .[]' <<<"$1"); do
    name=$(curl -s -H "Authorization: Bearer $JIRA_PAT" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${k}?fields=customfield_10102,customfield_10003,summary" \
      | jq -r '.fields.customfield_10102 // .fields.customfield_10003 // .fields.summary // "?"' 2>/dev/null)
    map=$(jq -c --arg k "$k" --arg n "${name:-?}" '. + {($k): $n}' <<<"$map")
  done
  echo "$map"
}

if [[ "$ACTION" == "search" ]]; then
  # A bare issue key (e.g. EAWM-8812) is fetched directly; anything else is
  # treated as free text for a JQL full-text search.
  if [[ "$SEARCH_QUERY" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
    RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer $JIRA_PAT" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${SEARCH_QUERY}?fields=${DETAIL_FIELDS}")

    HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
    RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")

    if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
      echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
      echo "$RESPONSE_BODY" >&2
      exit 1
    fi

    ISSUES_JSON=$(jq -c '[.]' <<<"$RESPONSE_BODY")
  else
    JQL="text ~ \"${SEARCH_QUERY}\""
    if [[ -n "$SEARCH_PROJECT" ]]; then
      JQL="project = ${SEARCH_PROJECT} AND ${JQL}"
    fi
    if [[ "$SEARCH_SPRINT_ONLY" -eq 1 ]]; then
      JQL="${JQL} AND sprint in openSprints()"
    fi

    ENCODED_JQL=$(jq -rn --arg jql "$JQL" '$jql|@uri')

    RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer $JIRA_PAT" \
      "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=${DETAIL_FIELDS}&maxResults=50")

    HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
    RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")

    if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
      echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
      echo "$RESPONSE_BODY" >&2
      exit 1
    fi

    COUNT=$(jq -r '.total' <<<"$RESPONSE_BODY")
    if [[ "$COUNT" == "0" ]]; then
      echo "No issues found matching '${SEARCH_QUERY}'${SEARCH_PROJECT:+ in project $SEARCH_PROJECT}${SEARCH_SPRINT_ONLY:+ in an open sprint}."
      exit 0
    fi

    ISSUES_JSON=$(jq -c '.issues' <<<"$RESPONSE_BODY")
  fi

  EPICS_JSON=$(fetch_epic_names "$ISSUES_JSON")
  unset JIRA_PAT

  # customfield_10000 (Sprint) comes back as a greenhopper Sprint object
  # toString(), same as 'mysprint' - pull id/name/state out with a regex
  # rather than parsing it as JSON.
  jq -r --arg base "$JIRA_BASE_URL" --argjson epics "$EPICS_JSON" '
    def v: if . == null or . == [] or . == "" then "(none)"
      elif type == "array" then map(if type == "object" then (.value // .name) else tostring end) | join(", ")
      elif type == "object" then (.value // .name // tostring)
      else tostring end;
    def link: if .outwardIssue then "  \(.type.outward) \(.outwardIssue.key) [\(.outwardIssue.fields.status.name)] \(.outwardIssue.fields.summary)"
      else "  \(.type.inward) \(.inwardIssue.key) [\(.inwardIssue.fields.status.name)] \(.inwardIssue.fields.summary)" end;
    .[] | .fields as $f |
    "Key:           \(.key)\n" +
    "URL:           \($base)/browse/\(.key)\n" +
    "Type:          \($f.issuetype.name)\n" +
    "Feature Type:  \(($f.customfield_32301 // $f.customfield_23300) | v)\n" +
    "Request Type:  \(($f.customfield_18400 // $f.customfield_16455) | v)\n" +
    "Status:        \($f.status.name)\n" +
    "Resolution:    \($f.resolution.name // "Unresolved")\n" +
    "Story State:   \($f.customfield_11700 | v)\n" +
    "Priority:      \($f.priority.name // "(none)")\n" +
    "Assignee:      \($f.assignee.displayName // "Unassigned")\n" +
    "Sprint:        \(($f.customfield_10104 // $f.customfield_10000 // ["(none)"])[-1])\n" +
    "Epic:          \(if ($f.customfield_10100 // $f.customfield_10001) then "\($f.customfield_10100 // $f.customfield_10001) - \($epics[$f.customfield_10100 // $f.customfield_10001] // "?")" else "(none)" end)\n" +
    "Labels:        \($f.labels | v)\n" +
    "Components:    \($f.components | v)\n" +
    "Fix Version:   \($f.fixVersions | v)\n" +
    "Story Points:  \(($f.customfield_10106 // $f.customfield_10100) | v)\n" +
    "Due Date:      \($f.duedate | v)\n" +
    "Target Start:  \(($f.customfield_11602 // $f.customfield_11704) | v)\n" +
    "Target End:    \(($f.customfield_11603 // $f.customfield_11705) | v)\n" +
    "Summary:       \($f.summary)\n" +
    "Description:\n\($f.description // "(none)")\n" +
    "Acceptance Criteria:\n\(($f.customfield_10200 // $f.customfield_10500) // "(none)")\n" +
    (if ($f.customfield_13214 | v) != "(none)" then "Resolution Description: \($f.customfield_13214)\n" else "" end) +
    "Links:\n" + (if ($f.issuelinks | length) > 0 then ($f.issuelinks | map(link) | join("\n")) else "  (none)" end) + "\n" +
    (if ($f.comment.comments | length) > 0 then
      "Comments:\n" + ($f.comment.comments | map("  [\(.author.displayName // .author.name)] \(.body)") | join("\n")) + "\n"
    else "" end) +
    "----------------------------------------"
  ' <<<"$ISSUES_JSON" | sed -E 's/^Sprint:.*id=([0-9]+),.*name=([^,]+),.*state=([A-Z]+).*$/Sprint:        id=\1 name=\2 state=\3/'
  exit 0
fi

if [[ "$ACTION" == "refine" ]]; then
  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer $JIRA_PAT" \
    "${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}?fields=${DETAIL_FIELDS},customfield_10006")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    unset JIRA_PAT
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  ISSUES_JSON=$(jq -c '[.]' <<<"$RESPONSE_BODY")
  EPICS_JSON=$(fetch_epic_names "$ISSUES_JSON")
  unset JIRA_PAT

  jq -r --arg base "$JIRA_BASE_URL" --argjson epics "$EPICS_JSON" '
    def blank: . == null or . == [] or ((type == "string") and (gsub("\\s"; "") == ""));
    def val: if type == "object" then .value else . end;
    def cap: ascii_downcase | (.[0:1] | ascii_upcase) + .[1:];
    def rating($text; $re): [$text | scan("(?i)" + $re + "[^\\n]*?\\b(low|medium|high)\\b")]
      | if length > 0 then (.[0][0] | cap) else null end;
    def row: "  " + (("[" + .s + "]" + "          ")[0:10]) + ((.n + ":" + "                    ")[0:19]) + .x;

    .[0] as $i | $i.fields as $f |
    # Strip wiki markup so "{*}I want{*}: to" reads as "I want to".
    (($f.description // "") | gsub("[*{}_]"; "") | gsub(":"; " ") | gsub("[ \\t]+"; " ")) as $d |
    ($d | ascii_downcase) as $dl |
    ($f.status.statusCategory.key == "done" or $f.resolution != null) as $done |
    ([($f.customfield_10006 // "") | tostring | capture("pullrequest=.*?stateCount=(?<n>[0-9]+)") | .n] | .[0] // "?") as $prs |
    ["Blocker","Critical","High","Medium","Low"] as $pri |
    ["Feature","Enabler","Spike","None"] as $fts |
    ["Development","Enhancement","Modernization","Research","Sustainment","Technical Debt","Other"] as $rts |

    [
      {s: (if $f.summary | blank then "MISSING" else "OK" end), n: "Title", x: ($f.summary // "add a summary title")},

      ($f.priority.name as $p |
        if $p == null then {s: "MISSING", n: "Priority", x: "set one of \($pri | join("/"))"}
        elif ($pri | index($p)) then {s: "OK", n: "Priority", x: $p}
        else {s: "GAP", n: "Priority", x: "\($p) is not one of \($pri | join("/"))"} end),

      ([ (if ($dl | test("\\bas an?\\b")) then empty else "As a" end),
         (if ($dl | test("\\bi want to\\b")) then empty else "I want to" end),
         (if ($dl | test("\\bso that\\b")) then empty else "So that" end) ] as $m |
        {s: (if ($m | length) == 0 then "OK" elif ($m | length) == 3 then "MISSING" else "GAP" end),
         n: "User story",
         x: (if ($m | length) == 0 then "As a / I want to / So that present" else "missing: " + ($m | join(", ")) end)}),

      ([["Complexity", rating($d; "complexity")], ["Volume", rating($d; "volume")], ["Risk", rating($d; "\\brisk\\b")]] as $r |
        [$r[] | select(.[1] == null) | .[0]] as $m |
        (($dl | index("so that")) as $st | ($dl | index("complexity")) as $cx | ($st != null and $cx != null and $cx < $st)) as $early |
        {s: (if ($m | length) == 3 then "MISSING" elif ($m | length) > 0 or $early then "GAP" else "OK" end),
         n: "Evaluation",
         x: (($r | map("\(.[0])=\(.[1] // "none")") | join(", "))
             + (if ($m | length) > 0 then " - needs Low/Medium/High for: " + ($m | join(", ")) else "" end)
             + (if $early then " - move after the user story" else "" end))}),

      (($f.customfield_10500 // "") as $ac |
        if ($ac | blank) then {s: "MISSING", n: "Acceptance crit.", x: "add GIVEN/WHEN/THEN (or checklist) criteria"}
        elif ($ac | test("(?i)\\bgiven\\b") and test("(?i)\\bwhen\\b") and test("(?i)\\bthen\\b")) then {s: "OK", n: "Acceptance crit.", x: "GIVEN/WHEN/THEN"}
        else {s: "OK", n: "Acceptance crit.", x: "checklist - use GIVEN/WHEN/THEN where possible"} end),

      (($f.customfield_23300 | val) as $ft |
        if $ft == null then {s: "MISSING", n: "Feature type", x: "set one of \($fts | join("/"))"}
        elif ($fts | index($ft)) then {s: "OK", n: "Feature type", x: $ft}
        else {s: "GAP", n: "Feature type", x: "\($ft) is not one of \($fts | join("/"))"} end),

      (($f.customfield_16455 | val) as $rt |
        if $rt == null then {s: "MISSING", n: "Request type", x: "set one of \($rts | join("/"))"}
        elif ($rts | index($rt)) then {s: "OK", n: "Request type", x: $rt}
        else {s: "GAP", n: "Request type", x: "\($rt) is not one of \($rts | join("/"))"} end)
    ] as $std |

    [
      (if $done and $prs == "0" then {s: "WARN", n: "Pull request", x: "issue is resolved but no pull request is linked"} else empty end),
      (if $done and ($f.customfield_13214 | blank | not) then {s: "WARN", n: "Resolution desc.", x: "\"\($f.customfield_13214)\" (Resolution: \($f.resolution.name // "none")) - confirm it supports closing"} else empty end),
      (if $done and (($f.customfield_11700 | val) == "Draft") then {s: "WARN", n: "Story state", x: "Draft on a resolved issue"} else empty end),
      (if $f.customfield_10001 == null then {s: "WARN", n: "Epic", x: "no Epic Link"} else empty end),
      (if $f.customfield_10000 | blank then {s: "WARN", n: "Sprint", x: "not in a sprint"} else empty end),
      (if $f.assignee == null then {s: "WARN", n: "Assignee", x: "unassigned"} else empty end),
      (if $f.duedate == null then {s: "WARN", n: "Due date", x: "not set"} else empty end),
      (if $f.fixVersions | blank then {s: "WARN", n: "Fix version", x: "not set"} else empty end)
    ] as $con |

    ([$std[], $con[]] | map(.s)) as $all |
    "Refinement check: \($i.key) - \($f.summary)\n" +
    "\($base)/browse/\($i.key)\n" +
    "Status: \($f.status.name) | Resolution: \($f.resolution.name // "Unresolved") | Epic: \(if $f.customfield_10001 then "\($f.customfield_10001) - \($epics[$f.customfield_10001] // "?")" else "(none)" end)\n\n" +
    "Standard (.github/prompts/refine-eawm.prompt.md):\n" + ($std | map(row) | join("\n")) + "\n\n" +
    "Consistency:\n" + (if ($con | length) == 0 then "  (no issues found)" else ($con | map(row) | join("\n")) end) + "\n\n" +
    "Totals: \([$all[] | select(. == "OK")] | length) OK, \([$all[] | select(. == "GAP")] | length) GAP, \([$all[] | select(. == "MISSING")] | length) MISSING, \([$all[] | select(. == "WARN")] | length) WARN"
  ' <<<"$ISSUES_JSON"
  exit 0
fi

if [[ "$ACTION" == "recentactivity" ]]; then
  if [[ -n "$RECENT_USER" ]]; then
    # A specific username was requested; use it directly for both the JQL
    # and changelog-author filter (no need to resolve the PAT owner).
    MY_NAME="$RECENT_USER"
    JQL_USER="\"${RECENT_USER}\""
  else
    # Default to the PAT owner: identify them via /myself so status
    # changes made by other people on the same issue can be filtered out
    # below.
    ME_RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer ${JIRA_PAT}" \
      "${JIRA_BASE_URL}/rest/api/2/myself")

    ME_HTTP_CODE=$(tail -n1 <<<"$ME_RESPONSE")
    ME_BODY=$(sed '$d' <<<"$ME_RESPONSE")

    if [[ ! "$ME_HTTP_CODE" =~ ^2 ]]; then
      unset JIRA_PAT
      echo "ERROR: Jira API returned HTTP $ME_HTTP_CODE (fetching current user)" >&2
      echo "$ME_BODY" >&2
      exit 1
    fi

    MY_NAME=$(jq -r '.name' <<<"$ME_BODY")
    JQL_USER="currentUser()"
  fi

  # Restrict to issues currently owned (assigned) by the same person who
  # made the status change - excludes stories worked/transitioned on
  # someone else's behalf.
  JQL="assignee = ${JQL_USER} AND status changed by ${JQL_USER} after -${RECENT_DAYS}d"
  if [[ -n "$RECENT_PROJECT" ]]; then
    JQL="project = ${RECENT_PROJECT} AND ${JQL}"
  fi

  ENCODED_JQL=$(jq -rn --arg jql "$JQL" '$jql|@uri')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,description&expand=changelog&maxResults=100")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  COUNT=$(jq -r '.total' <<<"$RESPONSE_BODY")
  if [[ "$COUNT" == "0" ]]; then
    echo "No issues owned by and status-changed by ${RECENT_USER:-you} in the last ${RECENT_DAYS} day(s)${RECENT_PROJECT:+ for project $RECENT_PROJECT}."
    exit 0
  fi

  # For each issue, scan changelog histories for 'status' field changes
  # authored by the target user within the requested window, and keep
  # only the most recent one (an issue may have several matching hops).
  jq -r --arg base "$JIRA_BASE_URL" --arg me "$MY_NAME" --argjson days "$RECENT_DAYS" '
    (now - ($days * 86400)) as $cutoff |
    .issues[] |
    (.changelog.histories // []) as $histories |
    ([
      $histories[] |
      select((.author.name | ascii_downcase) == ($me | ascii_downcase)) |
      . as $h |
      ($h.created | sub("\\.[0-9]+"; "") | strptime("%Y-%m-%dT%H:%M:%S%z") | mktime) as $ts |
      select($ts >= $cutoff) |
      ($h.items[] | select(.field == "status")) as $item |
      {created: $h.created, ts: $ts, from: $item.fromString, to: $item.toString}
    ] | sort_by(.ts) | last) as $lastChange |
    select($lastChange != null) |
    "Key:         \(.key)\n" +
    "URL:         \($base)/browse/\(.key)\n" +
    "Status:      \(.fields.status.name)\n" +
    "Changed:     \($lastChange.from) -> \($lastChange.to) on \($lastChange.created[0:10])\n" +
    "Summary:     \(.fields.summary)\n" +
    "Description:\n\(.fields.description // "(none)")\n" +
    "----------------------------------------"
  ' <<<"$RESPONSE_BODY"
  exit 0
fi

if [[ "$ACTION" == "futureactivity" ]]; then
  # Same ownership criteria as 'recentactivity' (assignee = the target
  # user), but looking forward: any issue in an open sprint that user
  # owns and hasn't yet finished, rather than issues already changed in
  # the past N days.
  if [[ -n "$FUTURE_USER" ]]; then
    JQL_ASSIGNEE="\"${FUTURE_USER}\""
  else
    JQL_ASSIGNEE="currentUser()"
  fi

  JQL="assignee = ${JQL_ASSIGNEE} AND sprint in openSprints() AND statusCategory != Done"
  if [[ -n "$FUTURE_PROJECT" ]]; then
    JQL="project = ${FUTURE_PROJECT} AND ${JQL}"
  fi

  ENCODED_JQL=$(jq -rn --arg jql "$JQL" '$jql|@uri')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,issuetype,description,customfield_10000&maxResults=100")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  COUNT=$(jq -r '.total' <<<"$RESPONSE_BODY")
  if [[ "$COUNT" == "0" ]]; then
    echo "No unfinished issues owned by ${FUTURE_USER:-you} in an open sprint${FUTURE_PROJECT:+ for project $FUTURE_PROJECT}."
    exit 0
  fi

  # customfield_10000 (Sprint) values come back as greenhopper Sprint
  # object toString()s, same as 'mysprint' - pull out id/name/state with
  # a small regex rather than parsing it as JSON.
  jq -r --arg base "$JIRA_BASE_URL" '
    .issues[] |
    "Key:         \(.key)\n" +
    "URL:         \($base)/browse/\(.key)\n" +
    "Type:        \(.fields.issuetype.name)\n" +
    "Status:      \(.fields.status.name)\n" +
    "Sprint:      \((.fields.customfield_10000 // ["(none)"])[-1])\n" +
    "Summary:     \(.fields.summary)\n" +
    "Description:\n\(.fields.description // "(none)")\n" +
    "----------------------------------------"
  ' <<<"$RESPONSE_BODY" | sed -E 's/^Sprint:.*id=([0-9]+),.*name=([^,]+),.*state=([A-Z]+).*$/Sprint:      id=\1 name=\2 state=\3/'
  exit 0
fi

if [[ "$ACTION" == "duesoon" ]]; then
  # Anything with the given label whose due date falls between today and
  # N days out (default 30) - a simple forward-looking planning report,
  # independent of assignee/sprint.
  JQL="labels = ${DUESOON_LABEL} AND duedate >= 0d AND duedate <= ${DUESOON_DAYS}d"
  if [[ -n "$DUESOON_PROJECT" ]]; then
    JQL="project = ${DUESOON_PROJECT} AND ${JQL}"
  fi
  JQL="${JQL} ORDER BY duedate ASC"

  ENCODED_JQL=$(jq -rn --arg jql "$JQL" '$jql|@uri')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,issuetype,description,duedate,assignee,labels&maxResults=100")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi

  COUNT=$(jq -r '.total' <<<"$RESPONSE_BODY")
  if [[ "$COUNT" == "0" ]]; then
    echo "No issues labeled '${DUESOON_LABEL}' due in the next ${DUESOON_DAYS} day(s)${DUESOON_PROJECT:+ for project $DUESOON_PROJECT}."
    exit 0
  fi

  jq -r --arg base "$JIRA_BASE_URL" '
    .issues[] |
    "Key:         \(.key)\n" +
    "URL:         \($base)/browse/\(.key)\n" +
    "Type:        \(.fields.issuetype.name)\n" +
    "Status:      \(.fields.status.name)\n" +
    "Due:         \(.fields.duedate // "(none)")\n" +
    "Assignee:    \(.fields.assignee.displayName // "Unassigned")\n" +
    "Summary:     \(.fields.summary)\n" +
    "Description:\n\(.fields.description // "(none)")\n" +
    "----------------------------------------"
  ' <<<"$RESPONSE_BODY"
  exit 0
fi

if [[ "$ACTION" == "removelabel" ]]; then
  # Two-step operation: fetch the issue's current labels, then PUT back
  # the list with the target label removed (all other labels preserved).
  GET_RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}?fields=labels")

  GET_HTTP_CODE=$(tail -n1 <<<"$GET_RESPONSE")
  GET_BODY=$(sed '$d' <<<"$GET_RESPONSE")

  if [[ ! "$GET_HTTP_CODE" =~ ^2 ]]; then
    unset JIRA_PAT
    echo "ERROR: Jira API returned HTTP $GET_HTTP_CODE (fetching $ISSUE_KEY)" >&2
    echo "$GET_BODY" >&2
    exit 1
  fi

  HAS_LABEL=$(jq -r --arg target "$REMOVE_LABEL" '(.fields.labels // []) | any(. == $target)' <<<"$GET_BODY")
  if [[ "$HAS_LABEL" != "true" ]]; then
    unset JIRA_PAT
    echo "Label '${REMOVE_LABEL}' is not present on ${ISSUE_KEY}; nothing to do."
    exit 0
  fi

  NEW_LABELS_JSON=$(jq -c --arg target "$REMOVE_LABEL" '(.fields.labels // []) | map(select(. != $target))' <<<"$GET_BODY")
  BODY_JSON=$(jq -n --argjson labels "$NEW_LABELS_JSON" '{fields: {labels: $labels}}')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer ${JIRA_PAT}" \
    -H "Content-Type: application/json" \
    -d "$BODY_JSON" \
    "${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    echo "Removed label '${REMOVE_LABEL}' from ${ISSUE_KEY} successfully (HTTP $HTTP_CODE)."
    exit 0
  else
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi
fi

if [[ "$ACTION" == "scorecard" ]]; then
  M_START="${SC_MONTH}-01"
  M_END=$(date -d "${M_START} +1 month" +%Y-%m-%d)
  P="$SC_PROJECT"
  SC_TMP=$(mktemp -d)
  trap 'rm -rf "$SC_TMP"' EXIT
  SC_QUERIES=()

  sc_count() {
    local enc body
    enc=$(jq -rn --arg j "$1" '$j|@uri')
    body=$(curl -s -f -H "Authorization: Bearer ${JIRA_PAT}" \
      "${JIRA_BASE_URL}/rest/api/2/search?jql=${enc}&maxResults=0") \
      || { echo "ERROR: Jira search failed for JQL: $1" >&2; return 1; }
    jq -r '.total' <<<"$body"
  }

  # Writes issues as NDJSON to a file; large JSON must not go through argv on Windows.
  sc_fetch() {
    local enc start=0 total=1 got
    enc=$(jq -rn --arg j "$1" '$j|@uri')
    : > "$4"
    while (( start < total )); do
      curl -s -f -H "Authorization: Bearer ${JIRA_PAT}" \
        "${JIRA_BASE_URL}/rest/api/2/search?jql=${enc}&fields=$2&maxResults=100&startAt=${start}${3:+&expand=$3}" \
        > "$4.page" || { echo "ERROR: Jira search failed for JQL: $1" >&2; return 1; }
      total=$(jq -r '.total' "$4.page")
      got=$(jq -r '.issues | length' "$4.page")
      jq -c '.issues[]' "$4.page" >> "$4"
      (( got == 0 )) && break
      start=$((start + got))
    done
  }

  # Lead / cycle time
  LC_JQL="project = ${P} AND issuetype in (Story, Bug) AND statusCategory = Done AND ((resolved >= \"${M_START}\" AND resolved < \"${M_END}\") OR status changed to (Resolved, Closed) during (\"${M_START}\", \"${M_END}\"))"
  sc_fetch "$LC_JQL" "issuetype,created,resolutiondate" changelog "$SC_TMP/lc.ndjson" || exit 1
  SC_QUERIES+=("Lead/Cycle candidates|$LC_JQL")
  LC=$(jq -s --arg m "$SC_MONTH" '
    def ts: (.[0:19] + "Z" | fromdateiso8601) as $t
      | .[-5:] as $o
      | (($o[1:3] | tonumber) * 3600 + ($o[3:5] | tonumber) * 60) as $off
      | if $o[0:1] == "-" then $t + $off else $t - $off end;
    def avg: if length == 0 then null else (add / length * 10 | round / 10) end;
    [ .[]
      | [ (.changelog.histories // [])[] | .created as $c | .items[]
          | select(.field == "status") | {c: $c, to: .toString} ] as $moves
      | ([ $moves[] | select(.to == "Resolved" or .to == "Closed") | .c ]
          + [ .fields.resolutiondate // empty ]
          | map({c: ., t: ts}) | min_by(.t)) as $end
      | select($end != null and $end.c[0:7] == $m)
      | ([ $moves[] | select(.to | IN("In Work", "In Progress", "Peer Review", "In Test")) | .c | ts ] | min) as $start
      | { type: .fields.issuetype.name,
          lead: (($end.t - (.fields.created | ts)) / 86400),
          cycle: (if $start != null and $start <= $end.t then ($end.t - $start) / 86400 else null end) }
    ] as $rows
    | { story_lead:  ([ $rows[] | select(.type == "Story") | .lead ] | avg),
        bug_lead:    ([ $rows[] | select(.type == "Bug") | .lead ] | avg),
        all_lead:    ([ $rows[].lead ] | avg),
        story_cycle: ([ $rows[] | select(.type == "Story" and .cycle != null) | .cycle ] | avg),
        bug_cycle:   ([ $rows[] | select(.type == "Bug" and .cycle != null) | .cycle ] | avg),
        all_cycle:   ([ $rows[] | select(.cycle != null) | .cycle ] | avg),
        n_story:     ([ $rows[] | select(.type == "Story") ] | length),
        n_bug:       ([ $rows[] | select(.type == "Bug") ] | length),
        no_cycle:    ([ $rows[] | select(.cycle == null) ] | length) }
  ' "$SC_TMP/lc.ndjson")

  # Releases
  curl -s -f -H "Authorization: Bearer ${JIRA_PAT}" \
    "${JIRA_BASE_URL}/rest/api/2/project/${P}/versions" > "$SC_TMP/versions.json" \
    || { echo "ERROR: could not fetch versions for ${P}" >&2; exit 1; }
  REL=$(jq --arg m "$SC_MONTH" '
    def day: . + "T00:00:00Z" | fromdateiso8601;
    [ .[] | select(.released == true and .releaseDate != null) ] | sort_by(.releaseDate) as $all
    | [ range(0; $all | length) as $i | $all[$i] | select(.releaseDate[0:7] == $m)
        | { id, name,
            gap: (if $i > 0 then ((.releaseDate | day) - ($all[$i - 1].releaseDate | day)) / 86400 else null end) } ] as $in
    | { count: ($in | length),
        cadence: ([ $in[].gap | select(. != null) ] | if length == 0 then null else (add / length * 10 | round / 10) end),
        ids: ([ $in[].id ] | join(",")),
        names: ([ $in[].name ] | join(", ")) }
  ' "$SC_TMP/versions.json")
  REL_IDS=$(jq -r '.ids' <<<"$REL")

  # Defect severity (by Priority)
  BUG_CREATED="project = ${P} AND issuetype = Bug AND created >= \"${M_START}\" AND created < \"${M_END}\""
  declare -A SEV_PRI=([1]="Blocker, Critical" [2]="High" [3]="Medium" [4]="Low")
  declare -A SEV
  for s in 1 2 3 4; do
    q="${BUG_CREATED} AND priority in (${SEV_PRI[$s]})"
    SEV[$s]=$(sc_count "$q") || exit 1
    SC_QUERIES+=("Sev $s|$q")
  done
  BUG_TOTAL=$(sc_count "$BUG_CREATED") || exit 1
  SEV_UNMAPPED=$(( BUG_TOTAL - SEV[1] - SEV[2] - SEV[3] - SEV[4] ))

  # Red zone risks
  RISK_JQL="project = ${P} AND issuetype = Risk AND statusCategory != Done"
  sc_fetch "$RISK_JQL" "customfield_16485,customfield_16486" "" "$SC_TMP/risk.ndjson" || exit 1
  SC_QUERIES+=("Open risks (filtered to High client-side)|$RISK_JQL")
  # Exposure fields come back as a Java toString, e.g. "Exposure{id=84, name='High', ...}".
  RED=$(jq -s '
    def exposure: if . == null then null elif type == "object" then .name
      else ([ tostring | capture("name=.(?<n>[A-Za-z ]+)") ][0].n) end;
    [ .[] | ((.fields.customfield_16486 | exposure) // (.fields.customfield_16485 | exposure))
      | select(. != null and test("High$")) ] | length
  ' "$SC_TMP/risk.ndjson")

  # Throughput
  q="project = ${P} AND issuetype = Story AND created >= \"${M_START}\" AND created < \"${M_END}\""
  STORIES_ADDED=$(sc_count "$q") || exit 1
  SC_QUERIES+=("Stories added|$q")
  STORIES_REL=0
  BUGS_REL=0
  if [[ -n "$REL_IDS" ]]; then
    q="project = ${P} AND issuetype = Story AND statusCategory = Done AND fixVersion in (${REL_IDS})"
    STORIES_REL=$(sc_count "$q") || exit 1
    SC_QUERIES+=("Stories released|$q")
    q="project = ${P} AND issuetype = Bug AND statusCategory = Done AND fixVersion in (${REL_IDS})"
    BUGS_REL=$(sc_count "$q") || exit 1
    SC_QUERIES+=("Defect fixes released|$q")
  fi
  unset JIRA_PAT

  na() { if [[ -z "$1" || "$1" == "null" ]]; then echo "N/A"; else echo "$1"; fi; }
  HEADERS=(
    "Story Lead Time (Average) (Days)"
    "Defect Lead Time (Average) (Days)"
    "Lead Time (Overall Average) (Days)"
    "Story Cycle Time (Average) (Days)"
    "Defect Cycle Time (Average) (Days)"
    "Cycle Time (Overall Average) (Days)"
    "Releases (Count)"
    "Release Cadence (Average) (Days)"
    "Failed Releases (Count)"
    "Sev 1 Prod/Non-Prod Defects (Count)"
    "Sev 2 Prod/Non-Prod Defects (Count)"
    "Sev 3 Prod/Non-Prod Defects (Count)"
    "Sev 4 Prod/Non-Prod Defects (Count)"
    "Red Zone Risks (# Open)"
    "Stories Added to Backlog (Count)"
    "Stories Released to Production (Count)"
    "Defect Fixes Released to Production (Count)"
  )
  VALUES=(
    "$(na "$(jq -r '.story_lead' <<<"$LC")")"
    "$(na "$(jq -r '.bug_lead' <<<"$LC")")"
    "$(na "$(jq -r '.all_lead' <<<"$LC")")"
    "$(na "$(jq -r '.story_cycle' <<<"$LC")")"
    "$(na "$(jq -r '.bug_cycle' <<<"$LC")")"
    "$(na "$(jq -r '.all_cycle' <<<"$LC")")"
    "$(jq -r '.count' <<<"$REL")"
    "$(na "$(jq -r '.cadence' <<<"$REL")")"
    "N/A"
    "${SEV[1]}" "${SEV[2]}" "${SEV[3]}" "${SEV[4]}"
    "$RED"
    "$STORIES_ADDED"
    "$STORIES_REL"
    "$BUGS_REL"
  )

  echo "${P} Product Scorecard - ${SC_MONTH}"
  echo "========================================================================"
  for i in "${!HEADERS[@]}"; do
    printf '  %-46s %s\n' "${HEADERS[$i]}" "${VALUES[$i]}"
  done
  echo
  echo "Notes:"
  echo "  Lead/cycle sample: $(jq -r '.n_story' <<<"$LC") stories, $(jq -r '.n_bug' <<<"$LC") defects first resolved/closed in ${SC_MONTH};"
  echo "    $(jq -r '.no_cycle' <<<"$LC") never entered an In Progress status (excluded from cycle time)."
  echo "  Releases in month: $(na "$(jq -r '.names' <<<"$REL")")"
  echo "  Failed Releases: not tracked in Jira - enter manually."
  echo "  Sev = Bug priority (Blocker/Critical=1, High=2, Medium=3, Low=4); ${SEV_UNMAPPED} bug(s) created in month had another priority."
  echo "  Red Zone = open Risks with Residual (else Inherent) risk High, as of $(date +%Y-%m-%d)."
  echo
  echo "JQL used:"
  for entry in "${SC_QUERIES[@]}"; do
    printf '  %s:\n    %s\n' "${entry%%|*}" "${entry#*|}"
  done

  if [[ -n "$SC_CSV" ]]; then
    if [[ ! -s "$SC_CSV" ]]; then
      jq -rn '$ARGS.positional | @csv' --args "Month" "${HEADERS[@]}" > "$SC_CSV"
    fi
    jq -rn '$ARGS.positional | @csv' --args "$SC_MONTH" "${VALUES[@]}" >> "$SC_CSV"
    echo
    echo "Appended ${SC_MONTH} row to ${SC_CSV}"
  fi
  exit 0
fi

if [[ "$ACTION" == "sprintreview" ]]; then
  SR_TMP=$(mktemp -d)
  trap 'rm -rf "$SR_TMP"' EXIT
  SR_JQL="project = ${SR_PROJECT} AND sprint = ${SR_SPRINT} AND statusCategory != Done AND issuetype not in subTaskIssueTypes()"
  SR_ENC=$(jq -rn --arg j "$SR_JQL" '$j|@uri')
  : > "$SR_TMP/issues.ndjson"
  start=0
  total=1
  while (( start < total )); do
    curl -s -f -H "Authorization: Bearer ${JIRA_PAT}" \
      "${JIRA_BASE_URL}/rest/api/2/search?jql=${SR_ENC}&fields=summary,status,issuetype,assignee,components,customfield_10000,issuelinks,comment,created&expand=changelog&maxResults=50&startAt=${start}" \
      > "$SR_TMP/page.json" || { echo "ERROR: Jira search failed for JQL: $SR_JQL" >&2; exit 1; }
    total=$(jq -r '.total' "$SR_TMP/page.json")
    got=$(jq -r '.issues | length' "$SR_TMP/page.json")
    jq -c '.issues[]' "$SR_TMP/page.json" >> "$SR_TMP/issues.ndjson"
    (( got == 0 )) && break
    start=$((start + got))
  done
  unset JIRA_PAT

  jq -s \
    --arg sid "$SR_SPRINT" \
    --arg since "$SR_SINCE" \
    --arg base "$JIRA_BASE_URL" \
    --arg re 'roll.?over|carr(y|ied).?over|next sprint|FY27Q1|SP-?1\b|move[ds]? to|push(ed)? to' '
    def d: .[0:19] + "Z" | fromdateiso8601;
    def lane: ascii_downcase as $s |
      if $s | test("to.?do") then "2 Sprint TO-DO"
      elif $s | test("planned|not started|backlog|open") then "1 Planned / Not Started"
      elif $s | test("in work|in progress|peer review|in test|in review") then "3 In Progress"
      else "4 Other (not Done)" end;
    def snip: gsub("\\s+"; " ") | .[0:200];
    map(
      .fields as $f |
      ($f.customfield_10000 // []) as $sp |
      (($sp | map(select(test("id=" + $sid + "[,\\]]"))) | .[0]) // "") as $cur |
      (if $since != "" then $since
       else ((try ($cur | capture("startDate=(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})").d) catch null) // "") end) as $from |
      ($f.assignee.name // "") as $who |
      ($f.comment.comments // []) as $cs |
      (([.changelog.histories[]? | select(any(.items[]; .field == "status")) | .created] | last) // $f.created) as $statusAt |
      {
        key,
        url: ($base + "/browse/" + .key),
        type: $f.issuetype.name,
        status: $f.status.name,
        lane: ($f.status.name | lane),
        assignee: ($f.assignee.displayName // "(unassigned)"),
        assigneeName: $who,
        summary: $f.summary,
        daysInStatus: ((now - ($statusAt | d)) / 86400 | floor),
        otherSprints: [$sp[] | select(. != $cur) | (try capture("name=(?<n>[^,\\]]*)").n catch .)],
        components: [$f.components[]?.name],
        blockers: [$f.issuelinks[]?
          | select(.type.inward == "is blocked by" and .inwardIssue != null
                   and .inwardIssue.fields.status.statusCategory.key != "done")
          | .inwardIssue.key + " (" + .inwardIssue.fields.status.name + ")"],
        lastComment: ($cs | last | if . then {author: .author.displayName, date: .created[0:10], text: (.body | snip)} else null end),
        rollover: ([$cs[] | select($who != "" and .author.name == $who and .created[0:10] >= $from and (.body | test($re; "i")))]
          | last | if . then {date: .created[0:10], text: (.body | snip)} else null end),
        from: $from
      }
    ) | sort_by(.lane, .assignee, .key)
  ' "$SR_TMP/issues.ndjson" > "$SR_TMP/rows.json"

  echo "Sprint review - sprint ${SR_SPRINT} (${SR_PROJECT}) - $(date +%Y-%m-%d)"
  echo "JQL: ${SR_JQL}"
  jq -r '
    def list: if length > 0 then join(", ") else "none" end;
    group_by(.lane)[] |
    "\n=== " + (.[0].lane | .[2:]) + " (" + (length | tostring) + ") ===",
    (.[] |
      "\n" + .key + "  [" + .status + "]  " + .type + " - " + .summary,
      "  URL:            " + .url,
      "  Assignee:       " + .assignee,
      "  Days in status: " + (.daysInStatus | tostring),
      "  Other sprints:  " + (.otherSprints | list),
      "  Components:     " + (.components | list),
      "  Blocked by:     " + (.blockers | list),
      "  Last comment:   " + (if .lastComment then .lastComment.date + " " + .lastComment.author + ": " + .lastComment.text else "(none)" end),
      "  Rollover note:  " + (if .rollover then "YES " + .rollover.date + ": " + .rollover.text else "NO (assignee comment since " + (if .from == "" then "?" else .from end) + " not found)" end))
  ' "$SR_TMP/rows.json"

  echo
  echo "=== Summary ==="
  jq -r '
    "  Total not Done: " + (length | tostring),
    (group_by(.lane)[] | "  " + (.[0].lane | .[2:]) + ": " + (length | tostring)),
    "",
    "NEEDS COMMENT (Planned / Sprint TO-DO / In Progress, no assignee rollover note):",
    ([.[] | select((.lane | startswith("4")) | not) | select(.rollover == null)]
      | if length == 0 then "  none" else .[] | "  " + .key + "  " + .assignee + " <" + .assigneeName + ">  [" + .status + "]" end)
  ' "$SR_TMP/rows.json"

  if [[ -n "$SR_CSV" ]]; then
    jq -r '
      ["Key","Lane","Status","Type","Summary","Assignee","AssigneeUser","DaysInStatus","OtherSprints","Components","BlockedBy","LastCommentDate","LastCommentAuthor","RolloverNote","RolloverDate","URL"],
      (.[] | [.key, (.lane | .[2:]), .status, .type, .summary, .assignee, .assigneeName, .daysInStatus,
              (.otherSprints | join("; ")), (.components | join("; ")), (.blockers | join("; ")),
              (.lastComment.date // ""), (.lastComment.author // ""),
              (if .rollover then "YES" else "NO" end), (.rollover.date // ""), .url])
      | @csv
    ' "$SR_TMP/rows.json" > "$SR_CSV"
    echo
    echo "Wrote ${SR_CSV}"
  fi

  exit 0
fi

if [[ "$ACTION" == "setcomponent" ]]; then
  # Sets the issue's components field to a single named component,
  # replacing any existing components (mirrors 'removelabel' style: a
  # GET to resolve the component name to an id, then a PUT to apply it).
  COMPONENTS_RESPONSE=$(curl -s -w '\n%{http_code}' \
    -H "Authorization: Bearer $JIRA_PAT" \
    "${JIRA_BASE_URL}/rest/api/2/project/${ISSUE_KEY%%-*}/components")

  COMPONENTS_HTTP_CODE=$(tail -n1 <<<"$COMPONENTS_RESPONSE")
  COMPONENTS_BODY=$(sed '$d' <<<"$COMPONENTS_RESPONSE")

  if [[ ! "$COMPONENTS_HTTP_CODE" =~ ^2 ]]; then
    unset JIRA_PAT
    echo "ERROR: Jira API returned HTTP $COMPONENTS_HTTP_CODE (fetching components)" >&2
    echo "$COMPONENTS_BODY" >&2
    exit 1
  fi

  COMPONENT_ID=$(jq -r --arg name "$SET_COMPONENT" '.[] | select(.name == $name) | .id' <<<"$COMPONENTS_BODY" | head -n1)
  if [[ -z "$COMPONENT_ID" ]]; then
    unset JIRA_PAT
    echo "ERROR: no component named '${SET_COMPONENT}' found in this project" >&2
    exit 1
  fi

  BODY_JSON=$(jq -n --arg id "$COMPONENT_ID" '{fields: {components: [{id: $id}]}}')

  RESPONSE=$(curl -s -w '\n%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer $JIRA_PAT" \
    -H "Content-Type: application/json" \
    -d "$BODY_JSON" \
    "${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}")

  HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
  RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
  unset JIRA_PAT

  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    echo "Set component '${SET_COMPONENT}' on ${ISSUE_KEY} successfully (HTTP $HTTP_CODE)."
    exit 0
  else
    echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi
fi

if [[ "$ACTION" == "dates" ]]; then
  for KEY in "${DATES_KEYS[@]}"; do
    RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer $JIRA_PAT" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${KEY}?fields=comment,status,resolutiondate")
    HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
    RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")

    echo "=== $KEY ==="
    if [[ "$HTTP_CODE" =~ ^2 ]]; then
      jq -r '.fields.status.name as $s | .fields.resolutiondate as $r |
        "Status: \($s)  Resolved: \($r)\n" +
        ((.fields.comment.comments // []) | map("  [\(.author.displayName)] \(.created)\n  \(.body[0:200])") | join("\n---\n"))' \
        <<<"$RESPONSE_BODY"
    else
      echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
      echo "$RESPONSE_BODY" >&2
    fi
    echo
  done
  unset JIRA_PAT
  exit 0
fi
  exit 0
fi

case "$ACTION" in
  comment)
    BODY_JSON=$(jq -n --arg body "$TEXT" '{body: $body}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/comment"
    METHOD="POST"
    ;;
  description)
    BODY_JSON=$(jq -n --arg desc "$TEXT" '{fields: {description: $desc}}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}"
    METHOD="PUT"
    ;;
  summary)
    BODY_JSON=$(jq -n --arg s "$TEXT" '{fields: {summary: $s}}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}"
    METHOD="PUT"
    ;;
  transition)
    TRANSITIONS_JSON=$(curl -s -H "Authorization: Bearer ${JIRA_PAT}" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/transitions")

    TRANSITION_ID=$(jq -r --arg target "$TEXT" '
      .transitions[]
      | select((.name | ascii_downcase) == ($target | ascii_downcase)
               or (.to.name | ascii_downcase) == ($target | ascii_downcase))
      | .id' <<<"$TRANSITIONS_JSON" | head -n1)

    if [[ -z "$TRANSITION_ID" ]]; then
      echo "ERROR: no direct transition to '$TEXT' is available from the current status of $ISSUE_KEY." >&2
      echo "Available transitions from the current status:" >&2
      jq -r '.transitions[] | "  - \"" + .name + "\" -> " + .to.name' <<<"$TRANSITIONS_JSON" >&2
      unset JIRA_PAT
      exit 1
    fi

    BODY_JSON=$(jq -n --arg id "$TRANSITION_ID" '{transition: {id: $id}}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/transitions"
    METHOD="POST"
    ;;
  create)
    EPIC_FIELD="${EPIC_LINK_FIELD:-customfield_10100}"
    SPRINT_FIELD="${SPRINT_FIELD:-customfield_10104}"
    EPIC_NAME_FIELD="${EPIC_NAME_FIELD:-customfield_10102}"
    BODY_JSON=$(jq -n \
      --arg project "$PROJECT_KEY" \
      --arg issuetype "$ISSUETYPE" \
      --arg summary "$SUMMARY" \
      --arg description "$DESCRIPTION" \
      --arg assignee "$ASSIGNEE" \
      --arg epic "$EPIC_LINK" \
      --arg epic_field "$EPIC_FIELD" \
      --arg sprint "$SPRINT_ID" \
      --arg sprint_field "$SPRINT_FIELD" \
      --arg labels "$LABELS" \
      --arg component "$COMPONENT" \
      --arg epicname "$EPIC_NAME" \
      --arg epicname_field "$EPIC_NAME_FIELD" \
      '{fields: ({project: {key: $project}, issuetype: {name: $issuetype}, summary: $summary, description: $description}
        + (if $assignee != "" then {assignee: {name: $assignee}} else {} end)
        + (if $epic != "" then {($epic_field): $epic} else {} end)
        + (if $sprint != "" then {($sprint_field): ($sprint | tonumber)} else {} end)
        + (if $labels != "" then {labels: ($labels | split(",") | map(select(length > 0)))} else {} end)
        + (if $component != "" then {components: [{name: $component}]} else {} end)
        + (if $epicname != "" then {($epicname_field): $epicname} else {} end))}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue"
    METHOD="POST"
    ;;
  assign)
    BODY_JSON=$(jq -n --arg name "$ASSIGNEE" '{name: $name}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/assignee"
    METHOD="PUT"
    ;;
  link)
    BODY_JSON=$(jq -n \
      --arg type "$LINK_TYPE" \
      --arg inward "$ISSUE_KEY" \
      --arg outward "$TARGET_KEY" \
      '{type: {name: $type}, inwardIssue: {key: $inward}, outwardIssue: {key: $outward}}')
    URL="${JIRA_BASE_URL}/rest/api/2/issueLink"
    METHOD="POST"
    ;;
  setparent)
    PARENT_FIELD="${PARENT_LINK_FIELD:-customfield_11601}"
    BODY_JSON=$(jq -n --arg parent "$PARENT_KEY" --arg field "$PARENT_FIELD" '{fields: {($field): $parent}}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}"
    METHOD="PUT"
    ;;
esac

RESPONSE=$(curl -s -w '\n%{http_code}' \
  -X "$METHOD" \
  -H "Authorization: Bearer ${JIRA_PAT}" \
  -H "Content-Type: application/json" \
  -d "$BODY_JSON" \
  "$URL")

HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")

# Clear the token from memory as soon as we're done with it.
unset JIRA_PAT

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  case "$ACTION" in
    create)
      NEW_KEY=$(jq -r '.key // empty' <<<"$RESPONSE_BODY")
      if [[ -n "$ASSIGNEE" ]]; then
        echo "Issue created successfully: ${NEW_KEY}, assigned to ${ASSIGNEE} (HTTP $HTTP_CODE)"
      else
        echo "Issue created successfully: ${NEW_KEY} (HTTP $HTTP_CODE)"
      fi
      ;;
    transition)
      echo "Transitioned $ISSUE_KEY to '$TEXT' successfully (HTTP $HTTP_CODE)."
      ;;
    assign)
      echo "Assigned $ISSUE_KEY to '$ASSIGNEE' successfully (HTTP $HTTP_CODE)."
      ;;
    link)
      echo "Linked $ISSUE_KEY to $TARGET_KEY with type '$LINK_TYPE' successfully (HTTP $HTTP_CODE)."
      ;;
    setparent)
      echo "Set Parent Link on $ISSUE_KEY to $PARENT_KEY successfully (HTTP $HTTP_CODE)."
      ;;
    *)
      echo "${ACTION^} updated successfully on $ISSUE_KEY (HTTP $HTTP_CODE)."
      ;;
  esac
else
  echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi
