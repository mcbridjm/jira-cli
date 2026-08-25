#!/usr/bin/env bash
#
# jira-issue-update.sh
#
# Updates or creates Jira issues via the REST API using a Personal Access
# Token (PAT). The token is loaded from a local .env file (variable PAT)
# rather than typed interactively, so this can be run non-interactively.
# If PAT is not already set in the environment and no .env is found, it
# falls back to an interactive silent prompt.
#
# Actions:
#   comment     - add a comment to an existing issue
#   description - replace an existing issue's description, optionally
#                 updating components and labels in the same call
#   transition  - move an existing issue to a new status (single workflow
#                 hop only - see notes below for multi-step workflows)
#   create      - create a new issue in a project, optionally setting its
#                 issue type, owner/assignee, Epic Link, and Sprint
#   clone       - create a new issue by cloning core fields from an
#                 existing issue, with optional field overrides
#   assign      - assign an existing issue to a user (by Jira username)
#   mysprint    - list issues assigned to the PAT owner in any open sprint
#                 (optionally scoped to one project), printing key, URL,
#                 status, issue type, description, and Sprint (id/name) for
#                 each - use this to find the numeric sprint id for
#                 create's --sprint option
#   field       - look up custom field ids by (partial, case-insensitive)
#                 name match, e.g. to (re)discover the Epic Link / Sprint
#                 field ids on this Jira instance
#
# Usage:
#   ./jira-issue-update.sh comment     <ISSUE-KEY> "<comment text>"          [env-file]
#   ./jira-issue-update.sh description <ISSUE-KEY> "<description text>" [--component <component-name>]... [--label <label>]... [--env <env-file>]
#   ./jira-issue-update.sh transition  <ISSUE-KEY> "<target status name>"   [env-file]
#   ./jira-issue-update.sh create      <PROJECT-KEY> "<summary>" "<description>" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]
#   ./jira-issue-update.sh clone       <SOURCE-ISSUE-KEY> [--project <PROJECT-KEY>] [--summary <summary>] [--description <description>] [--type <issuetype>] [--assignee <username>] [--no-assignee] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]
#   ./jira-issue-update.sh assign      <ISSUE-KEY> <assignee-username>       [env-file]
#   ./jira-issue-update.sh mysprint    [PROJECT-KEY] [env-file]
#   ./jira-issue-update.sh field       <search-term> [env-file]
#
# Examples:
#   ./jira-issue-update.sh comment EAWM-7384 "Applied topology spread constraints."
#   ./jira-issue-update.sh description EAWM-7384 "$(cat new-description.txt)"
#   ./jira-issue-update.sh description EAWM-7384 "$(cat new-description.txt)" --component FY27Q1 --label committed
#   ./jira-issue-update.sh transition EAWM-7384 "Resolved"
#   ./jira-issue-update.sh create EAWM "Promote topology spread constraints to Production" "$(cat followup-desc.txt)" --type Story --assignee adam.schaefer2@va.gov
#   ./jira-issue-update.sh create EAWM "Research OCR true-up" "$(cat desc.txt)" --epic EAWM-8837 --sprint 52476 --assignee adam.schaefer2@va.gov
#   ./jira-issue-update.sh create EAWM "Release objective" "$(cat desc.txt)" --type Initiative --component FY27Q1 --label committed
#   ./jira-issue-update.sh clone EAWM-7384 --summary "Follow-up: topology spread constraints"
#   ./jira-issue-update.sh clone EAWM-7384 --project EAWM --type Story --component FY27Q1 --label committed --no-assignee
#   ./jira-issue-update.sh assign EAWM-7385 adam.schaefer2@va.gov
#   ./jira-issue-update.sh mysprint EAWM
#   ./jira-issue-update.sh field sprint
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
#   `./jira-issue-update.sh mysprint <PROJECT-KEY>` to see the active
#   sprint's id/name from issues already in it, or
#   `./jira-issue-update.sh field sprint` / `field epic` to re-discover the
#   field ids if this ever changes (e.g. on a different Jira project or
#   instance where custom field ids differ).
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
# The .env file (default: ./.env, next to this script) must define:
#   PAT=<your jira personal access token>
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <comment|description|transition|create|clone|assign|mysprint|field> ..." >&2
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
  description)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 description <ISSUE-KEY> \"<description text>\" [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
      exit 1
    fi
    ISSUE_KEY="$1"
    TEXT="$2"
    shift 2
    DESCRIPTION_COMPONENTS_JSON='[]'
    DESCRIPTION_LABELS_JSON='[]'
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --component)
          DESCRIPTION_COMPONENTS_JSON=$(jq -cn --argjson a "$DESCRIPTION_COMPONENTS_JSON" --arg v "$2" '$a + [{name:$v}]')
          shift 2
          ;;
        --label)
          DESCRIPTION_LABELS_JSON=$(jq -cn --argjson a "$DESCRIPTION_LABELS_JSON" --arg v "$2" '$a + [$v]')
          shift 2
          ;;
        --env)
          ENV_FILE="$2"
          shift 2
          ;;
        *)
          # Backward compatibility: allow trailing positional env file.
          if [[ $# -eq 1 && "$1" != --* ]]; then
            ENV_FILE="$1"
            shift
          else
            echo "ERROR: unrecognized description option '$1'" >&2
            echo "Usage: $0 description <ISSUE-KEY> \"<description text>\" [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
            exit 1
          fi
          ;;
      esac
    done
    ;;
  comment|transition)
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
      echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
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
    CREATE_COMPONENTS_JSON='[]'
    CREATE_LABELS_JSON='[]'
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)     ISSUETYPE="$2"; shift 2 ;;
        --assignee) ASSIGNEE="$2"; shift 2 ;;
        --epic)     EPIC_LINK="$2"; shift 2 ;;
        --sprint)   SPRINT_ID="$2"; shift 2 ;;
        --component)
          CREATE_COMPONENTS_JSON=$(jq -cn --argjson a "$CREATE_COMPONENTS_JSON" --arg v "$2" '$a + [{name:$v}]')
          shift 2
          ;;
        --label)
          CREATE_LABELS_JSON=$(jq -cn --argjson a "$CREATE_LABELS_JSON" --arg v "$2" '$a + [$v]')
          shift 2
          ;;
        --env)      ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized create option '$1'" >&2
          echo "Usage: $0 create <PROJECT-KEY> \"<summary>\" \"<description>\" [--type <issuetype>] [--assignee <username>] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
          exit 1
          ;;
      esac
    done
    ;;
  clone)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 clone <SOURCE-ISSUE-KEY> [--project <PROJECT-KEY>] [--summary <summary>] [--description <description>] [--type <issuetype>] [--assignee <username>] [--no-assignee] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
      exit 1
    fi
    SOURCE_ISSUE_KEY="$1"
    shift
    CLONE_PROJECT_KEY=""
    CLONE_SUMMARY=""
    CLONE_DESCRIPTION=""
    CLONE_ISSUETYPE=""
    CLONE_ASSIGNEE=""
    CLONE_NO_ASSIGNEE=0
    CLONE_EPIC_LINK=""
    CLONE_SPRINT_ID=""
    CLONE_COMPONENTS_JSON='[]'
    CLONE_LABELS_JSON='[]'
    CLONE_COMPONENTS_OVERRIDE=0
    CLONE_LABELS_OVERRIDE=0
    ENV_FILE="$(dirname "$0")/.env"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project) CLONE_PROJECT_KEY="$2"; shift 2 ;;
        --summary) CLONE_SUMMARY="$2"; shift 2 ;;
        --description) CLONE_DESCRIPTION="$2"; shift 2 ;;
        --type) CLONE_ISSUETYPE="$2"; shift 2 ;;
        --assignee) CLONE_ASSIGNEE="$2"; shift 2 ;;
        --no-assignee) CLONE_NO_ASSIGNEE=1; shift ;;
        --epic) CLONE_EPIC_LINK="$2"; shift 2 ;;
        --sprint) CLONE_SPRINT_ID="$2"; shift 2 ;;
        --component)
          CLONE_COMPONENTS_OVERRIDE=1
          CLONE_COMPONENTS_JSON=$(jq -cn --argjson a "$CLONE_COMPONENTS_JSON" --arg v "$2" '$a + [{name:$v}]')
          shift 2
          ;;
        --label)
          CLONE_LABELS_OVERRIDE=1
          CLONE_LABELS_JSON=$(jq -cn --argjson a "$CLONE_LABELS_JSON" --arg v "$2" '$a + [$v]')
          shift 2
          ;;
        --env) ENV_FILE="$2"; shift 2 ;;
        *)
          echo "ERROR: unrecognized clone option '$1'" >&2
          echo "Usage: $0 clone <SOURCE-ISSUE-KEY> [--project <PROJECT-KEY>] [--summary <summary>] [--description <description>] [--type <issuetype>] [--assignee <username>] [--no-assignee] [--epic <EPIC-KEY>] [--sprint <sprint-id>] [--component <component-name>]... [--label <label>]... [--env <env-file>]" >&2
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
  *)
    echo "ERROR: action must be one of comment, description, transition, create, clone, assign, mysprint, field (got '$ACTION')" >&2
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

case "$ACTION" in
  comment)
    BODY_JSON=$(jq -n --arg body "$TEXT" '{body: $body}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue/${ISSUE_KEY}/comment"
    METHOD="POST"
    ;;
  description)
    BODY_JSON=$(jq -n \
      --arg desc "$TEXT" \
      --argjson components "$DESCRIPTION_COMPONENTS_JSON" \
      --argjson labels "$DESCRIPTION_LABELS_JSON" \
      '{fields: ({description: $desc}
        + (if ($components | length) > 0 then {components: $components} else {} end)
        + (if ($labels | length) > 0 then {labels: $labels} else {} end))}')
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
      --argjson components "$CREATE_COMPONENTS_JSON" \
      --argjson labels "$CREATE_LABELS_JSON" \
      '{fields: ({project: {key: $project}, issuetype: {name: $issuetype}, summary: $summary, description: $description}
        + (if $assignee != "" then {assignee: {name: $assignee}} else {} end)
        + (if $epic != "" then {customfield_10001: $epic} else {} end)
        + (if $sprint != "" then {customfield_10000: ($sprint | tonumber)} else {} end)
        + (if ($components | length) > 0 then {components: $components} else {} end)
        + (if ($labels | length) > 0 then {labels: $labels} else {} end))}')
    URL="${JIRA_BASE_URL}/rest/api/2/issue"
    METHOD="POST"
    ;;
  clone)
    SOURCE_RESPONSE=$(curl -s -w '\n%{http_code}' \
      -H "Authorization: Bearer ${JIRA_PAT}" \
      "${JIRA_BASE_URL}/rest/api/2/issue/${SOURCE_ISSUE_KEY}?fields=project,issuetype,summary,description,assignee,components,labels,customfield_10001")

    SOURCE_HTTP_CODE=$(tail -n1 <<<"$SOURCE_RESPONSE")
    SOURCE_BODY=$(sed '$d' <<<"$SOURCE_RESPONSE")

    if [[ ! "$SOURCE_HTTP_CODE" =~ ^2 ]]; then
      echo "ERROR: failed to read source issue '$SOURCE_ISSUE_KEY' (HTTP $SOURCE_HTTP_CODE)" >&2
      echo "$SOURCE_BODY" >&2
      unset JIRA_PAT
      exit 1
    fi

    SRC_PROJECT_KEY=$(jq -r '.fields.project.key // empty' <<<"$SOURCE_BODY")
    SRC_ISSUETYPE=$(jq -r '.fields.issuetype.name // empty' <<<"$SOURCE_BODY")
    SRC_SUMMARY=$(jq -r '.fields.summary // empty' <<<"$SOURCE_BODY")
    SRC_DESCRIPTION=$(jq -r '.fields.description // empty' <<<"$SOURCE_BODY")
    SRC_ASSIGNEE=$(jq -r '.fields.assignee.name // empty' <<<"$SOURCE_BODY")
    SRC_EPIC_LINK=$(jq -r '.fields.customfield_10001 // empty' <<<"$SOURCE_BODY")
    SRC_COMPONENTS_JSON=$(jq -c '[.fields.components[]? | {name: .name}]' <<<"$SOURCE_BODY")
    SRC_LABELS_JSON=$(jq -c '[.fields.labels[]?]' <<<"$SOURCE_BODY")

    FINAL_PROJECT_KEY="${CLONE_PROJECT_KEY:-$SRC_PROJECT_KEY}"
    FINAL_ISSUETYPE="${CLONE_ISSUETYPE:-$SRC_ISSUETYPE}"
    FINAL_SUMMARY="${CLONE_SUMMARY:-$SRC_SUMMARY}"
    FINAL_DESCRIPTION="${CLONE_DESCRIPTION:-$SRC_DESCRIPTION}"
    FINAL_EPIC_LINK="${CLONE_EPIC_LINK:-$SRC_EPIC_LINK}"

    if [[ "$CLONE_NO_ASSIGNEE" -eq 1 ]]; then
      FINAL_ASSIGNEE=""
    elif [[ -n "$CLONE_ASSIGNEE" ]]; then
      FINAL_ASSIGNEE="$CLONE_ASSIGNEE"
    else
      FINAL_ASSIGNEE="$SRC_ASSIGNEE"
    fi

    if [[ "$CLONE_COMPONENTS_OVERRIDE" -eq 1 ]]; then
      FINAL_COMPONENTS_JSON="$CLONE_COMPONENTS_JSON"
    else
      FINAL_COMPONENTS_JSON="$SRC_COMPONENTS_JSON"
    fi

    if [[ "$CLONE_LABELS_OVERRIDE" -eq 1 ]]; then
      FINAL_LABELS_JSON="$CLONE_LABELS_JSON"
    else
      FINAL_LABELS_JSON="$SRC_LABELS_JSON"
    fi

    BODY_JSON=$(jq -n \
      --arg project "$FINAL_PROJECT_KEY" \
      --arg issuetype "$FINAL_ISSUETYPE" \
      --arg summary "$FINAL_SUMMARY" \
      --arg description "$FINAL_DESCRIPTION" \
      --arg assignee "$FINAL_ASSIGNEE" \
      --arg epic "$FINAL_EPIC_LINK" \
      --arg sprint "$CLONE_SPRINT_ID" \
      --argjson components "$FINAL_COMPONENTS_JSON" \
      --argjson labels "$FINAL_LABELS_JSON" \
      '{fields: ({project: {key: $project}, issuetype: {name: $issuetype}, summary: $summary, description: $description}
        + (if $assignee != "" then {assignee: {name: $assignee}} else {} end)
        + (if $epic != "" then {customfield_10001: $epic} else {} end)
        + (if $sprint != "" then {customfield_10000: ($sprint | tonumber)} else {} end)
        + (if ($components | length) > 0 then {components: $components} else {} end)
        + (if ($labels | length) > 0 then {labels: $labels} else {} end))}')
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
    create|clone)
      NEW_KEY=$(jq -r '.key // empty' <<<"$RESPONSE_BODY")
      if [[ "$ACTION" == "clone" ]]; then
        echo "Issue cloned successfully: ${SOURCE_ISSUE_KEY} -> ${NEW_KEY} (HTTP $HTTP_CODE)."
      elif [[ -n "$ASSIGNEE" ]]; then
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
