# Prompt for Next Agent: Tasks.md Full Rewrite

## Your Mission

You are a specialized agent tasked with rewriting the `tasks.md` file for the correcciones-homologacion specification to achieve a 9.5/10 quality score from the spec-task-validator agent.

**Current Status**: Draft exists with 7/10 score - NEEDS_IMPROVEMENT
**Target Status**: 9.5/10 - READY FOR IMPLEMENTATION
**Work Required**: Full rewrite with 4 critical fixes, 3 additions, and comprehensive restructuring
**Estimated Time**: 4-5 hours

---

## CRITICAL: Read These Documents First

**YOU MUST READ THESE FILES BEFORE STARTING** (in this exact order):

1. **TASKS_REWRITE_HANDOFF.md** (THIS DIRECTORY) - Your complete instruction manual
   - Contains all issues to fix
   - Contains examples of correct format
   - Contains step-by-step workflow
   - Contains success criteria
   - **READ THIS ENTIRE FILE BEFORE PROCEEDING**

2. **.specify/templates/tasks-template.md** - The template you must follow
   - This is your formatting source of truth
   - All sections in template must appear in your rewrite
   - All task format rules must be followed

3. **tasks.md** (THIS DIRECTORY) - Current draft to rewrite
   - Review current structure (42 tasks)
   - Understand what needs to change
   - Preserve good content (descriptions, file paths, leverage references)

4. **requirements.md** (THIS DIRECTORY) - 8 requirements to cover
   - Requirement 1.0: Best-Match Selection Algorithm (CRITICAL)
   - Requirement 2.0: Transmission Recovery
   - Requirement 3.0: Brand Consolidation
   - Requirement 4.0: Model Normalization
   - Requirement 5.0: Version Cleaning
   - Requirement 6.0: Technical Specs Standardization
   - Requirement 7.0: Insurer-Specific Normalization
   - Requirement 8.0: Data Validation and Quality Gates

5. **design.md** (THIS DIRECTORY) - 6 components to implement
   - Component 1: Best-Match Selection (lines 117-233)
   - Component 2: Brand Consolidation Map (lines 234-279)
   - Component 3: Transmission Recovery (lines 280-321)
   - Component 4: Model Normalization (lines 322-368)
   - Component 5: Version Cleaning (lines 369-425)
   - Component 6: Token Deduplication (lines 426-444)

6. **HANDOFF.md** (THIS DIRECTORY) - Original project guidance
   - Task breakdown guidance (lines 160-201)
   - Code patterns to follow (lines 202-248)
   - Testing strategy (lines 250-278)

---

## What You Need to Do

### Phase 1: Understanding (30 minutes)

**READ ALL DOCUMENTS LISTED ABOVE**. Do not skip this step. The handoff document contains critical details about:
- 4 CRITICAL issues that cause the 7/10 score
- 3 MISSING INFORMATION areas to add
- Specific examples of correct vs incorrect formatting
- Complete task splitting instructions (42 → 111 tasks)
- Success criteria for each validation task
- Insurer-specific requirements table

### Phase 2: Rewrite Tasks.md (4 hours)

**Follow the 9-step workflow in TASKS_REWRITE_HANDOFF.md** (lines 530-591):

1. **Step 1**: Read all reference documents (you're doing this now)
2. **Step 2**: Create new document structure from template
3. **Step 3**: Convert all task formats from `### T001:` to `- [ ] 1.`
4. **Step 4**: Split 11 non-atomic tasks into 33 atomic sub-tasks (A/B/C pattern)
5. **Step 5**: Add success criteria to validation tasks
6. **Step 6**: Add missing tasks (Task 0, Phase 4 deployment)
7. **Step 7**: Update supporting sections (parallel examples, dependencies graph)
8. **Step 8**: Validate rewrite (self-check all requirements met)
9. **Step 9**: Final quality check (read as if implementing)

**CRITICAL FORMATTING RULES**:
- ✅ Use checkbox format: `- [ ] 1. Task description`
- ✅ Include all fields: File, Action, Leverage, Requirements, Time, Dependencies, Parallel
- ✅ Use 2-space indentation for nested bullets
- ✅ No bold formatting in field names (File not **File**)
- ✅ No backticks around file paths (src/... not `src/...`)
- ✅ Add [P] marker ONLY if different file AND no dependencies
- ✅ Reference specific requirement subsections (1.1, 1.3, not just 1.0)

### Phase 3: Validate with Spec-Task-Validator (15 minutes)

**After completing the rewrite, you MUST validate it**:

```
Use the Task tool to launch spec-task-validator agent with this prompt:

"Validate the rewritten tasks.md for correcciones-homologacion specification.

Context:
- Specification directory: .claude/specs/correcciones-homologacion/
- Tasks file: .claude/specs/correcciones-homologacion/tasks.md (REWRITTEN)
- Requirements: .claude/specs/correcciones-homologacion/requirements.md
- Design: .claude/specs/correcciones-homologacion/design.md

This is a rewrite that addresses previous 7/10 validation issues:
1. Added all missing template sections
2. Converted to checkbox format
3. Split non-atomic tasks (42 → 111 tasks)
4. Added success criteria to validation tasks
5. Added deployment tasks (Phase 4)
6. Added file verification task (Task 0)

Expected Result: Quality score 9.0-10.0 (EXCELLENT / READY FOR IMPLEMENTATION)

Please provide detailed validation including:
- Overall quality score (target: 9.5/10)
- Confirmation that all 4 critical issues are fixed
- Verification that all 111 tasks are atomic (5-30 min, single purpose)
- Requirement and component coverage (should be 100%)
- Any remaining issues that need addressing"
```

**If validator returns < 9.0 score**: Fix identified issues and re-validate.
**If validator returns ≥ 9.0 score**: Proceed to Phase 4.

### Phase 4: Present to User (5 minutes)

**Once validation passes with 9.0+ score, present summary to user**:

```markdown
## Tasks.md Rewrite Complete ✅

I've successfully rewritten the tasks.md file for correcciones-homologacion specification.

### Results:
- **Quality Score**: X.X/10 (was 7/10) - READY FOR IMPLEMENTATION
- **Task Count**: 111 tasks (was 42)
- **Atomic Tasks**: 100% (all 5-30 minutes, single purpose)
- **Requirement Coverage**: 8/8 requirements (100%)
- **Component Coverage**: 6/6 design components (100%)

### Changes Made:

**1. Template Compliance** (CRITICAL ISSUE #1):
- ✅ Added Task Overview section
- ✅ Added Steering Document Compliance section
- ✅ Added Atomic Task Requirements section
- ✅ Added Task Format Guidelines section

**2. Checkbox Format** (CRITICAL ISSUE #2):
- ✅ Converted all 111 tasks from `### TX:` to `- [ ] Number.` format
- ✅ Added all required fields (Leverage, Requirements, Dependencies, Parallel)
- ✅ Removed bold formatting, fixed indentation

**3. Task Atomicity** (CRITICAL ISSUE #3):
- ✅ Split 11 composite tasks into 33 atomic sub-tasks (XA, XB, XC pattern)
- ✅ Each task now 5-30 minutes, single purpose
- ✅ Added insurer-specific requirements to appropriate sub-tasks

**4. Success Criteria** (CRITICAL ISSUE #4):
- ✅ Added measurable success criteria to all validation tasks (104-108)
- ✅ Added success criteria to all deployment tasks (109-111)
- ✅ Specified pass/fail conditions, expected outputs, verification methods

**5. Missing Information**:
- ✅ Added Task 0: Verify project structure and file paths
- ✅ Added Phase 4: Deployment (3 new tasks)
- ✅ Added test framework setup instructions

**6. Supporting Sections**:
- ✅ Updated Parallel Execution Examples with new task numbers
- ✅ Updated Dependencies Graph with new structure
- ✅ Updated Validation Checklist with 111-task breakdown

### File Modified:
- `.claude/specs/correcciones-homologacion/tasks.md` (complete rewrite)

### Validation Report:
[Paste validator output here showing 9.0+ score]

### Next Steps:
1. **Review the rewritten tasks.md** - Check if structure and content meet your expectations
2. **Approve for implementation** - If satisfied, we can proceed to generate task commands
3. **Request changes** - If anything needs adjustment, I can make targeted revisions

Would you like to review the rewritten file, or shall I proceed to generate task commands for implementation?
```

---

## Important Notes

### DO NOT:
- ❌ Skip reading the handoff document completely
- ❌ Keep the old `### TX:` header format
- ❌ Leave composite tasks unsplit (must split T007, T010, T013, T016, T019, T022, T025, T028, T031, T034, T037)
- ❌ Forget to add Phase 4 (deployment tasks)
- ❌ Forget to add Task 0 (file verification)
- ❌ Present to user without validator approval (must be 9.0+ score)
- ❌ Use vague success criteria ("test passes" is NOT acceptable)

### DO:
- ✅ Read TASKS_REWRITE_HANDOFF.md line by line (it's your instruction manual)
- ✅ Follow the template format exactly (.specify/templates/tasks-template.md)
- ✅ Split all composite tasks into atomic sub-tasks (A/B/C pattern)
- ✅ Add specific success criteria with measurable outputs
- ✅ Include all insurer-specific requirements from Req 7.0 table (handoff lines 323-334)
- ✅ Validate with spec-task-validator before presenting to user
- ✅ Use TodoWrite tool to track your progress through the 9 steps

---

## Success Criteria

**Your rewrite is complete when**:

1. ✅ Validator returns 9.0-10.0 score (not 7.0, not 8.5 - must be 9.0+)
2. ✅ All 111 tasks use checkbox format `- [ ] Number.` (not `### TX:`)
3. ✅ All tasks have 7 required fields: File, Action, Leverage, Requirements, Time, Dependencies, Parallel
4. ✅ All 8 requirements mapped to specific tasks (100% coverage)
5. ✅ All 6 design components mapped to specific tasks (100% coverage)
6. ✅ All tasks are atomic: 5-30 minutes, single purpose, 1-3 files
7. ✅ Phase 4 exists with 3 deployment tasks (109-111)
8. ✅ Task 0 exists for file verification
9. ✅ Tasks 4, 104-111 have detailed success criteria
10. ✅ User approves the final rewrite

---

## Workflow Summary

```
START
  ↓
1. Read TASKS_REWRITE_HANDOFF.md (30 min)
   - Understand all 4 critical issues
   - Review examples of correct format
   - Note all required changes
  ↓
2. Read template, current tasks.md, requirements.md, design.md (30 min)
  ↓
3. Create new document structure (15 min)
   - Copy template sections
   - Add correcciones-specific content
  ↓
4. Convert task format (60 min)
   - Change all headers to checkboxes
   - Add missing fields
   - Fix indentation
  ↓
5. Split non-atomic tasks (90 min)
   - Split T007 → 7A, 7B, 7C
   - Split T010 → 10A, 10B, 10C (+ Zurich-specific)
   - [Repeat for all 11 insurers]
   - Renumber all tasks (42 → 111)
  ↓
6. Add success criteria (45 min)
   - Add to tasks 4, 104-111
   - Include measurable outputs
  ↓
7. Add missing tasks (30 min)
   - Add Task 0 (verification)
   - Add Phase 4 (deployment)
  ↓
8. Update supporting sections (30 min)
   - Parallel execution examples
   - Dependencies graph
   - Validation checklist
  ↓
9. Self-validate (15 min)
   - Check all checkboxes
   - Verify all fields present
   - Confirm 111 tasks numbered correctly
  ↓
10. Run spec-task-validator (15 min)
   - Launch validator agent
   - Review score (must be 9.0+)
   - Fix any issues if < 9.0
  ↓
11. Present to user (5 min)
   - Show score and changes
   - Await approval
  ↓
END
```

**Total Time**: ~5 hours

---

## Example Task Conversion

**To help you understand the required changes, here's a complete example:**

### BEFORE (Current - 7/10 score):
```markdown
### T007: Add enhanced model and version normalization to MAPFRE
- **File**: `src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- **Action**:
  - Extend normalizeModelo() with NUEVO prefix removal, body type cleanup
  - Extend cleanVersionString() with escape char removal, HP+AUT separation
  - Implement fixInvalidDoorCounts() for BMW model numbers
  - Add deduplicateTokens() if not present
- **Time**: 30 minutes
- **Dependencies**: T006 (same file, sequential)
- **Parallel**: No
- **Leverage**: Design.md Components 4-6, Qualitas deduplicateTokens()
```

### AFTER (Target - 9.5/10 score):
```markdown
- [ ] 7A. Add enhanced model normalization to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Locate existing normalizeModelo() function
    - Add NUEVO/NUEVA/NEW prefix removal: `normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, '')`
    - Add Mazda-specific: Remove "MAZDA" or "MA" prefix if marca === 'MAZDA'
    - Add Mercedes-specific: Remove "MERCEDES" prefix, replace "KLASSE" with "CLASE"
    - Add BMW-specific: Normalize "SERIE X5" to "X5"
    - Keep existing body type removal, prefix cleanup (lines 731-800 in Qualitas)
  - Leverage: Design.md Component 4 (lines 322-363), Qualitas normalizeModelo() pattern
  - Requirements: 4.1 (NUEVO prefix), 4.2 (Brand prefixes), 4.3 (Body types), 4.4 (Generic prefixes)
  - Time: 15 minutes
  - Dependencies: 6 (needs transmission recovery)
  - Parallel: No (same file as Task 6)

- [ ] 7B. Add enhanced version cleaning to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Locate existing cleanVersionString() function
    - Add escape character removal at start of function:
      - `cleaned.replace(/\\"/g, '')` (escaped quotes)
      - `cleaned.replace(/\\\\/g, '')` (backslashes)
      - `cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, ' ')` (all quote types)
    - Add HP+AUT separation: `cleaned.replace(/(\d+)HPAUT/gi, '$1HP AUT')`
    - Add fixInvalidDoorCounts() helper function (see Design.md lines 404-419):
      - Remove BMW model numbers: 300PUERTAS, 320PUERTAS, 328PUERTAS, 335PUERTAS
      - Fix truck notation: 3500PUERTAS → 4PUERTAS
      - Remove invalid: 0PUERTAS, [6-9]PUERTAS, [100+]PUERTAS
    - Call fixInvalidDoorCounts() after existing normalization steps
  - Leverage: Design.md Component 5 (lines 369-420), existing cleanVersionString() structure
  - Requirements: 5.1 (Escape chars), 5.2 (HPAUT pattern), 5.3 (Invalid doors)
  - Time: 15 minutes
  - Dependencies: 7A (same file, sequential)
  - Parallel: No

- [ ] 7C. Add intelligent token deduplication to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Check if deduplicateTokens() function already exists (search for "deduplicateTokens")
    - If NOT present, copy from Qualitas (lines 569-609):
      - Function signature: `deduplicateTokens(tokens)`
      - Logic: Preserve different spec types (2.0L vs 2PUERTAS), first occurrence wins
      - Helper: `isNumericSpecification(token)` to detect 2.0L, 5PUERTAS patterns
    - Apply deduplicateTokens() to version string after all cleaning steps
    - Verify no duplicate tokens in final version (e.g., "5PUERTAS...5PUERTAS" → "5PUERTAS")
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6 (Duplicate tokens), 5.7 (Preserve spec types), 5.8 (Conditional append)
  - Time: 15 minutes
  - Dependencies: 7B (same file, sequential)
  - Parallel: No
```

**Notice the differences**:
1. ✅ Checkbox format instead of header
2. ✅ Split into 3 atomic tasks (15 min each) instead of 1 composite (30 min)
3. ✅ Specific requirement subsections (4.1, 4.2) instead of high-level (4.0)
4. ✅ Detailed action steps with code examples
5. ✅ No bold formatting, no backticks around paths
6. ✅ Consistent 2-space indentation

---

## Emergency Contact

**If you get stuck or unclear on anything**:

1. **Re-read TASKS_REWRITE_HANDOFF.md** - It has examples for every issue
2. **Re-read the template** - It shows exact formatting rules
3. **Ask the user** - They can clarify requirements or provide missing information

**Only ask user if**:
- Critical information is truly missing (e.g., test framework preference)
- Requirements are ambiguous or contradictory
- File paths cannot be verified

**Do NOT ask user for**:
- Formatting questions (template has all answers)
- Task splitting guidance (handoff document has complete instructions)
- Success criteria examples (handoff document has all examples)

---

## You've Got This! 🚀

This is a large rewrite task, but you have everything you need:
- ✅ Complete instruction manual (TASKS_REWRITE_HANDOFF.md)
- ✅ Exact template to follow (.specify/templates/tasks-template.md)
- ✅ Good foundation to build on (current tasks.md)
- ✅ Clear success criteria (9.5/10 score)
- ✅ Validation tool to check your work (spec-task-validator)

**Follow the 9-step workflow, use TodoWrite to track progress, validate before presenting, and you'll produce a 9.5/10 tasks.md file that's ready for implementation.**

**Start by reading TASKS_REWRITE_HANDOFF.md completely. Good luck!**

---

**Document Version**: 1.0
**Created**: 2025-10-17
**Target Agent**: Claude Code (Haiku 4.5)
**Expected Duration**: 4-5 hours
**Expected Outcome**: tasks.md with 9.5/10 quality score, 111 atomic tasks, user approval
