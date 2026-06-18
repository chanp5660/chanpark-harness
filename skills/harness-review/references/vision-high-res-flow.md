# Vision High-Res Flow (Opus 4.7)

Typical scenario-based flows for leveraging the high-resolution vision capability
(short-side up to 2576px) of Opus 4.7 in harness-review.

> **Resolution limit**: 2576px on the short side is the safe operational ceiling. Pre-resize images that exceed this limit.
> For detailed guidance, see [`docs/opus-4-7-vision-usage.md`](../../../docs/opus-4-7-vision-usage.md).

---

## Scenario 1: PDF Page Review

For reviewing PDFs such as specification documents, design documents, or release notes.

### Flow

1. **Identify the page range**

   Passing the entire PDF at once increases token consumption, so first get an overview of the page structure.

   ```
   Read tool: file_path="<path>.pdf", pages="1-5"
   ```

2. **Check the effective DPI per page**

   When a PDF has a high DPI, the short side may exceed 2576px after rendering.
   If it does, request a re-export at a lower DPI (see the usage guide for details).

3. **Load the target pages with Read**

   ```
   Read tool: file_path="<path>.pdf", pages="<target page range>"
   ```

   The Read tool passes the pages specified with the pages parameter to the vision model.
   Up to 20 pages can be specified per call.

4. **Pass to the Reviewer agent**

   Route the loaded page content into the harness-review flow (Step 2: 5 perspectives).
   The Reviewer evaluates visual layout, diagrams, and code snippets as well.

5. **Batch processing (for high page counts)**

   Split PDFs with more than 20 pages into batches of 20 pages each.

   ```
   pages="1-20"  → review → record findings
   pages="21-40" → review → record findings
   ...
   Integrate all verdicts at the end
   ```

### Verdict Criteria

PDF reviews are treated with a `static` reviewer_profile, evaluating the following:

| Perspective | Check |
|------|------------|
| **Quality** | Are diagrams sufficiently described? Is the order of steps clear? |
| **Accessibility** | Are there any image-only pages without alt text? |
| **AI Residuals** | Incomplete markers such as "TODO", "TBD", "Draft" |

---

## Scenario 2: Architecture Diagram Review

For reviewing images such as system diagrams, ER diagrams, or sequence diagrams.

### Flow

1. **Check the image resolution**

   ```bash
   # macOS: check resolution with sips
   sips -g pixelWidth -g pixelHeight diagram.png

   # With ImageMagick
   identify diagram.png
   ```

   If the short side is 2576px or less, the image can be passed directly via the Read tool.
   If it exceeds this, pre-resize (see the usage guide for details).

2. **Load the image with Read**

   ```
   Read tool: file_path="diagram.png"
   ```

   Opus 4.7 can read up to 2576px, allowing it to analyze fine labels and arrows.

3. **Prepare context to pass to the Reviewer agent**

   ```
   Please review the following architecture diagram.
   Target: <diagram type (system diagram / ER diagram / sequence diagram, etc.)> for <system name>
   Review focus: <review purpose (consistency check / change diff check / security check, etc.)>
   ```

4. **Evaluation criteria**

   | Perspective | Check |
   |------|------------|
   | **Security** | Are authentication flows, authorization boundaries, and encryption requirements reflected in the diagram? |
   | **Quality** | Are inter-component dependencies clear? Is single responsibility maintained? |
   | **Performance** | Are potential bottlenecks (synchronous processing / N+1 / no caching, etc.) visualized? |

5. **Cross-check with implementation code**

   After the diagram review, cross-check against the corresponding implementation code using the Code Review flow to verify consistency.

---

## Scenario 3: UI Screenshot Review

For scoring Web / mobile UI screenshots using the `--ui-rubric` option.

### Flow

1. **Prepare screenshots**

   Take screenshots of the target pages and components.
   In Retina / HiDPI environments, the size is often double the logical pixel dimensions.

   ```bash
   # macOS: screencapture command
   screencapture -x screenshot.png

   # Check resolution
   sips -g pixelWidth -g pixelHeight screenshot.png
   ```

2. **Check resolution and resize if needed**

   Resize if the short side exceeds 2576px (see the usage guide for details).
   If 2576px or less, pass directly via the Read tool.

3. **Evaluate with harness-review --ui-rubric**

   ```
   /harness-review --ui-rubric
   ```

   Before running, load the screenshot with the Read tool and pass it to the Reviewer agent:

   ```
   Read tool: file_path="screenshot.png"
   ```

4. **4-axis scoring (see ui-rubric.md)**

   | Axis | Evaluation |
   |----|---------|
   | **Design Quality** | Visual hierarchy, spacing, color consistency |
   | **Originality** | Uniqueness, brand expression |
   | **Craft** | Pixel precision, animations, micro-interactions |
   | **Functionality** | Completeness of user flows, consideration of error states |

5. **Multi-resolution comparison (mobile / tablet / desktop)**

   Consecutively Read screenshots at each resolution in the same session and
   have the Reviewer agent evaluate responsive support together.

   ```
   Read tool: file_path="mobile.png"    # ~375×812
   Read tool: file_path="tablet.png"    # ~768×1024
   Read tool: file_path="desktop.png"   # ~1440×900
   ```

---

## Connecting to the Reviewer Agent

In all three scenarios above, after loading images / PDFs with the Read tool,
use the following common pattern to connect to the Reviewer agent.

### Connecting in breezing mode

When Lead receives a task with vision input from Worker:

1. Worker returns the image/PDF path in `files_changed`
2. Lead reads that path with the Read tool, attaches vision context, and runs the review
3. Reviewer agent returns a verdict in the `review-result.v1` schema

```json
// Example of additional context passed to Reviewer
{
  "vision_inputs": [
    { "type": "image", "path": "diagram.png", "role": "architecture_diagram" },
    { "type": "pdf",  "path": "spec.pdf",    "role": "specification", "pages": "1-10" }
  ],
  "review_context": "Review of changes including images and PDFs"
}
```

### Reviewer behavior when receiving image input

- The Reviewer treats image input the same as "ordinary diff text" and returns `review-result.v1`
- For `observations[].location`, write entries like `"diagram.png:overall"` / `"spec.pdf:p3"`
- If critical / major cannot be determined from the image alone, limit the finding to `minor` or `recommendation`
- Verdict criteria (critical / major / minor / recommendation) do not change based on whether vision input is present

---

## Batch Processing Guidelines

When continuously reviewing multiple images / PDF pages:

| Situation | Recommended approach |
|------|--------------|
| PDF 20 pages or fewer | Specify all pages in a single Read call |
| PDF 21 or more pages | Split into batches of 20 → consolidate findings |
| 1–5 images | Consecutive Read → review together |
| 6 or more images | Batches of 5 → consolidate verdict at the end |
| Mixed high-resolution images | Pre-resize before processing (see usage guide) |

In batch processing, accumulate `observations` from each batch and
determine the final verdict based on the presence of `critical` / `major` findings after all batches complete.
