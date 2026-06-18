# UI Rubric Reviewer Profile

A review profile specialized in visual quality, invoked by `harness-review --ui-rubric`.
Instead of leaving UI quality assessment as "just a feeling," this profile scores 4 axes on a 0–10 scale and delivers a verdict.

---

## Understanding the 4 Axes

### 1. Design Quality

- What it evaluates: information organization, spacing, visual flow, readability
- Common low scores: text too crowded, element priority not communicated
- Common high scores: what to look at is conveyed naturally

### 2. Originality

- What it evaluates: low sense of familiarity, intentional individuality, choice of expression
- Common low scores: generic template layout used as-is
- Common high scores: a distinctive presentation suited to the brand or problem

### 3. Craft

- What it evaluates: care in details, alignment, spacing, typography, state transitions
- Common low scores: subtle misalignments, uneven spacing, rough hover / active states
- Common high scores: consistent throughout the details with minimal roughness

### 4. Functionality

- What it evaluates: ease of use without confusion, whether primary flows work, practical usability
- Common low scores: button or form intent unclear, primary flow broken
- Common high scores: users never have to wonder what to do next

---

## Anchor Examples (0 / 5 / 10)

| Axis | 0 | 5 | 10 |
|---|---|---|---|
| Design Quality | Unclear what is being shown; hard to read | Minimally readable but weak organization | Information priority and visual flow are clear |
| Originality | Looks like an off-the-shelf template | Some creative touches but a weak impression | Distinctive personality suited to the problem; memorable |
| Craft | Alignment and spacing are inconsistent; details are rough | No major breakdowns but finishing is loose | Spacing, typography, and state changes are all carefully done |
| Functionality | Primary flow is hard to understand; difficult to use | Primary operations work but there are moments of confusion | Primary flow is natural; users can act without hesitation |

---

## Scoring Method

1. Score each of the 4 axes on a 0–10 scale
2. If `review.rubric_target` is provided, use its per-axis values as thresholds
3. If `review.rubric_target` is not provided, use default threshold=6 for all 4 axes
4. If any axis falls below the threshold → `REQUEST_CHANGES`
5. If all axes meet or exceed the threshold → `APPROVE`

### Example `rubric_target`

```json
{
  "design": 7,
  "originality": 6,
  "craft": 8,
  "functionality": 9
}
```

---

## Output Format

- Set `reviewer_profile` to `"ui-rubric"` without exception
- In `observations`, write the reason a score was lowered in language understandable to non-experts
- For each axis, include at least one suggestion for "what to fix to raise the score"

### Example Output

```json
{
  "reviewer_profile": "ui-rubric",
  "verdict": "REQUEST_CHANGES",
  "ui_rubric": {
    "scores": {
      "design": 7,
      "originality": 5,
      "craft": 8,
      "functionality": 8
    },
    "targets": {
      "design": 6,
      "originality": 6,
      "craft": 6,
      "functionality": 6
    }
  }
}
```

---

## Scoring Notes

- Do not award high scores based on flashiness alone
- Do not inflate Originality simply because something is "unusual"
- When usability is broken, prioritize Functionality and apply a strict score
- Judge by **intent and completeness**, not by personal design preference
