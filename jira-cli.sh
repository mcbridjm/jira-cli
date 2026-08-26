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
#   transition  - move an existing issue to a new status (single workflow
#                 hop only - see notes below for multi-step workflows)
#   create      - create a new issue in a project, optionally setting its
#                 issue type, owner/assignee, Epic Link, and Sprint
#   assign      - assign an existing issue to a user (by Jira username)
#   mysprint    - list issues assigned to the PAT owner in any open sprint
#                 (optionally scoped to one project), printing key, URL,
#                 status, issue type, description, and Sprint (id/name) for
#                 each - use this to find the numeric sprint id for
#                 create's --sprint option
#   field       - look up custom field ids by (partial, case-insensitive)
#                 name match, e.g. to (re)discover the Epic Link / Sprint
#                 field ids on this Jira instance
#   search      - look up issue(s) by issue key OR free-text search, and
#                 print the FULL content (summary, status, type, assignee,
#                 sprint, full description, comments) of each match -
#                 optionally scoped to a project and/or the open sprint
#   recentactivity - list issues owned by (assigned to) a given user
#                 (default: the PAT owner, or a specific Jira username via
#                 --user) where that same user changed the status within
#                 the last N days (default 7), optionally scoped to one
#                 project - prints key, URL, full description, and the
#                 most recent status transition (from/to + date) made by
#                 that user, for building status-report summaries
#
# Usage:
#   ./jira-cli.sh comment     <ISSUE-KEY> "<comment text>"          [env-file]
#   ./jira-cli.sh description <ISSUE-KEY> "<description text>"     [env-file]
#   ./jira-cli.sh transition  <ISSUE-KEY> "<target status name>"   [env-file]
#   ./jira-cli.sh create      <PROJECT-KEY> "<summary>" "<description>" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--env <env-file>]
#   ./jira-cli.sh assign      <ISSUE-KEY> <assignee-username>       [env-file]
#   ./jira-cli.sh mysprint    [PROJECT-KEY] [env-file]
#   ./jira-cli.sh field       <search-term> [env-file]
#   ./jira-cli.sh search      <ISSUE-KEY | "text to search">  [--project <PROJECT-KEY>] [--sprint] [--env <env-file>]
#   ./jira-cli.sh recentactivity [--days <n>] [--project <PROJECT-KEY>] [--user <jira-username>] [--env <env-file>]
#
# Examples:
#   ./jira-cli.sh comment EAWM-7384 "Applied topology spread constraints."
#   ./jira-cli.sh description EAWM-7384 "$(cat new-description.txt)"
#   ./jira-cli.sh transition EAWM-7384 "Resolved"
#   ./jira-cli.sh create EAWM "Promote topology spread constraints to Production" "$(cat followup-desc.txt)" --type Story --assignee adam.schaefer2@va.gov
#   ./jira-cli.sh create EAWM "Research OCR true-up" "$(cat desc.txt)" --epic EAWM-8837 --sprint 52476 --assignee adam.schaefer2@va.gov
#   ./jira-cli.sh assign EAWM-7385 adam.schaefer2@va.gov
#   ./jira-cli.sh mysprint EAWM
#   ./jira-cli.sh field sprint
#   ./jira-cli.sh search EAWM-8812
#   ./jira-cli.sh search "Account Re-use" --project EAWM --sprint
#   ./jira-cli.sh recentactivity
#   ./jira-cli.sh recentactivity --days 14 --project EAWM
#   ./jira-cli.sh recentactivity --user macklin.mcbride@va.gov --days 7
#
# Notes on 'assign' / create's --assignee (the issue "owner"):
#   The assignee value must be the Jira account's "name" (username), which
#   on this Server/Data Center instance is the user's login (often their
#   email address, e.g. adam.schaefer2@va.gov) - NOT a Cloud accountId.
#   You can look it up with:
#     curl -s -H "Authorization: Bearer $PAT" \
#       "https://jira.devops.va.gov/rest/api/2/user/search?username=<email>"
#
# Notes on create's --epic / --sprint:
#   These map to custom fields discovered via the 'field' action on this
#   instance: Epic Link = customfield_10001 (takes the epic's issue key,
#   e.g. EAWM-8837) and Sprint = customfield_10000 (takes the sprint's
#   numeric id, e.g. 52476 - NOT its display name). Run
#   `./jira-cli.sh mysprint <PROJECT-KEY>` to see the active
#   sprint's id/name from issues already in it, or
#   `./jira-cli.sh field sprint` / `field epic` to re-discover the
#   field ids if this ever changes (e.g. on a different Jira project or
#   instance where custom field ids differ).
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
# The .env file (default: ./.env, next to this script) must define:
#   PAT=<your jira personal access token>
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <comment|description|transition|create|assign|mysprint|field|search|recentactivity> ..." >&2
  echo "Run with -h for full usage." >&2
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed -e 's/^# \{0,1\}//'
  exit 0
fi

ACTION="$1"
shift
JIRA_BASE_URL="https://jira.devops.va.gov"

case "$ACTION" in
  comment|description|transition)
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
      echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--env <env-file>]" >&2
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
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)     ISSUETYPE="$2"; shift 2 ;;
        --assignee) ASSIGNEE="$2"; shift 2 ;;
        --epic)     EPIC_LINK="$2"; shift 2 ;;
        --sprint)   SPRINT_ID="$2"; shift 2 ;;
        --env)      ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized create option '$1'" >&2
          echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--env <env-file>]" >&2
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
  *)
    echo "ERROR: action must be one of comment, description, transition, create, assign, mysprint, field, search, recentactivity (got '$ACTION')" >&2
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
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,issuetype,description,customfield_10000")

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
    "Sprint:      \((.fields.customfield_10000 // ["(none)"])[-1])\n" +
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

if [[ "$ACTION" == "search" ]]; then
  # A bare issue key (e.g. EAWM-8812) is fetched directly; anything else is
  # treated as free text for a JQL full-text search.
  if [[ "$SEARCH_QUERY" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
    RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer $JIRA_PAT" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${SEARCH_QUERY}?fields=summary,status,issuetype,assignee,description,comment,customfield_10000")

    HTTP_CODE=$(tail -n1 <<<"$RESPONSE")
    RESPONSE_BODY=$(sed '$d' <<<"$RESPONSE")
    unset JIRA_PAT

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
      "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=summary,status,issuetype,assignee,description,comment,customfield_10000&maxResults=50")

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
      echo "No issues found matching '${SEARCH_QUERY}'${SEARCH_PROJECT:+ in project $SEARCH_PROJECT}${SEARCH_SPRINT_ONLY:+ in an open sprint}."
      exit 0
    fi

    ISSUES_JSON=$(jq -c '.issues' <<<"$RESPONSE_BODY")
  fi

  # customfield_10000 (Sprint) comes back as a greenhopper Sprint object
  # toString(), same as 'mysprint' - pull id/name/state out with a regex
  # rather than parsing it as JSON.
  jq -r --arg base "$JIRA_BASE_URL" '
    .[] |
    "Key:         \(.key)\n" +
    "URL:         \($base)/browse/\(.key)\n" +
    "Type:        \(.fields.issuetype.name)\n" +
    "Status:      \(.fields.status.name)\n" +
    "Assignee:    \(.fields.assignee.displayName // "Unassigned")\n" +
    "Sprint:      \((.fields.customfield_10000 // ["(none)"])[-1])\n" +
    "Summary:     \(.fields.summary)\n" +
    "Description:\n\(.fields.description // "(none)")\n" +
    (if (.fields.comment.comments | length) > 0 then
      "Comments:\n" + (.fields.comment.comments | map("  [\(.author.displayName // .author.name)] \(.body)") | join("\n")) + "\n"
    else "" end) +
    "----------------------------------------"
  ' <<<"$ISSUES_JSON" | sed -E 's/^Sprint:.*id=([0-9]+),.*name=([^,]+),.*state=([A-Z]+).*$/Sprint:      id=\1 name=\2 state=\3/'
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
      select(.author.name == $me) |
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
    BODY_JSON=$(jq -n \
      --arg project "$PROJECT_KEY" \
      --arg issuetype "$ISSUETYPE" \
      --arg summary "$SUMMARY" \
      --arg description "$DESCRIPTION" \
      --arg assignee "$ASSIGNEE" \
      --arg epic "$EPIC_LINK" \
      --arg sprint "$SPRINT_ID" \
      '{fields: ({project: {key: $project}, issuetype: {name: $issuetype}, summary: $summary, description: $description}
        + (if $assignee != "" then {assignee: {name: $assignee}} else {} end)
        + (if $epic != "" then {customfield_10001: $epic} else {} end)
        + (if $sprint != "" then {customfield_10000: ($sprint | tonumber)} else {} end))}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue"
    METHOD="POST"
    ;;
  assign)
    BODY_JSON=$(jq -n --arg name "$ASSIGNEE" '{name: $name}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/assignee"
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
    *)
      echo "${ACTION^} updated successfully on $ISSUE_KEY (HTTP $HTTP_CODE)."
      ;;
  esac
else
  echo "ERROR: Jira API returned HTTP $HTTP_CODE" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi
