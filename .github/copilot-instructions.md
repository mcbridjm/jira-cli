# USPS MAS EMMS (UME) & Jira Project Rules

## Story Closing Rule
**Mandatory Requirement for Closing / Resolving Stories:**
Whenever a story is closed (transitioned to `Done` / `Resolved`):
1. **Resolution Summary Generation**: You MUST generate a structured **Resolution Description** synthesizing:
   - **Original Scope & Story Goal**: What was requested and delivered.
   - **Acceptance Criteria Verification**: Clear confirmation that all Acceptance Criteria items were validated and satisfied.
   - **Summary of Completed Actions**: Detailed synthesis of decisions, outcomes, deliverables, and Box links documented across the story's comments and history.
2. **Comment Posting**: Post the synthesized Resolution Description as a dedicated closing comment on the story before or during the transition to `Done`.
3. **Approval Gate**: Recommend the closing comment and transition; obtain explicit user approval before executing the transition in Jira.

---

## Story Refinement Rules

### Agile Story Quality Standard
A well-formed story MUST meet all of the following before it is considered refined:

**1. User-Centric Structure (As a / I want / So that)**
Every story description must open with:
> As a `<persona>`, I want `<goal>`, so that `<benefit>`.
- `<persona>` — the specific role or user type, not a generic "user"
- `<goal>` — what the user wants to accomplish (not how it will be implemented)
- `<benefit>` — the business or user value delivered; must be distinct from the goal

**2. INVEST Criteria**
Evaluate each story against all six INVEST dimensions; flag any that fail:
| Dimension | Check |
|-----------|-------|
| **I**ndependent | Can be delivered without being blocked by another in-flight story |
| **N**egotiable | Scope is open to discussion; not a rigid spec |
| **V**aluable | Delivers clear, demonstrable user or business value |
| **E**stimable | Team can size it with reasonable confidence |
| **S**mall | Completable within a single sprint |
| **T**estable | Has concrete, verifiable acceptance criteria |

**3. Measurable Acceptance Criteria**
Acceptance criteria define "done" and must be:
- Written in **GIVEN / WHEN / THEN** format whenever functional behavior is described, or as a checklist for operational/infrastructure steps
- Specific and measurable — avoid vague phrases like "works correctly" or "is fast"
- Inclusive of non-functional requirements (performance, error handling, security) where relevant
- Free of placeholder text (e.g. unanswered questions left in the AC field)

**4. Value over Implementation**
- The story sentence describes *what* and *why*, never *how*
- Technical implementation details belong in acceptance criteria notes or sub-tasks, not the story sentence itself

### General Refinement Rules
- When reviewing or refining any Jira issue, apply the Agile Story Quality Standard above together with the team's Complexity/Volume/Risk evaluation.
- Never overwrite existing description content; append structured sections and use comments to capture detailed context.
- Recommend only; make no Jira edits until the user explicitly approves.

---

## Other Guidelines
- When reviewing or refining any EAWM Jira issue, follow [refine-eawm.prompt.md](prompts/refine-eawm.prompt.md). Recommend only; make no Jira edits until the user approves.
- When assisting with annual performance evaluations, follow [annual-performance-evaluation.prompt.md](prompts/annual-performance-evaluation.prompt.md).
