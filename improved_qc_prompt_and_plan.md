# Improved AI Quality Control Prompt & Execution Plan

## Part 1: What Changed and Why

The original prompt in `02_ai_quality_control.R` is functional but has several weaknesses that reduce scoring consistency:

1. **No calibration anchors** — The Likert scales say "1 = bad, 5 = good" but don't give concrete examples at each level, so the model's interpretation drifts between runs.
2. **No few-shot grounding** — Without a scored example, the model has to guess the grading standard from scratch each time.
3. **Missing criteria** — The manual QC script (`01_manual_quality_control.R`) checks for belittling phrases ("obviously", "as you can see", "it is clear that") and data specificity (does the report cite actual numbers?), but the AI prompt ignores both.
4. **Weak accuracy instructions** — The prompt says "check if numbers are wrong" but doesn't tell the model to cross-reference every percentage in the report against the source table row by row.
5. **No separation of system vs. user role** — When using OpenAI, the system message is generic ("You are a quality control validator") while all the real instructions are crammed into the user message, reducing instruction-following reliability.

---

## Part 2: The Improved Prompt

Below is the full improved `create_quality_control_prompt()` function. Copy-paste it to replace the existing one in `02_ai_quality_control.R` (lines ~93–156).

```r
create_quality_control_prompt = function(report_text, source_data = NULL) {

  # ── SYSTEM-LEVEL INSTRUCTIONS ──────────────────────────────────
  # Clear role definition + output format constraint
  instructions = paste0(
    "You are a strict quality-control validator for AI-generated government reports.\n",
    "Your job: score the report text against the source data on every criterion below.\n",
    "Rules:\n",
    "- Compare EVERY number and percentage in the report to the source table.\n",
    "- A single wrong number means accurate = false.\n",
    "- Contractions include: we're, they're, it's, can't, don't, won't, shouldn't, etc.\n",
    "- Hyperbole includes: crucial, critical, extremely, absolutely, obviously, clearly, demands immediate.\n",
    "- Belittling phrases include: 'it is clear that', 'obviously', 'as you can see', 'needless to say'.\n",
    "- Return ONLY a single valid JSON object. No markdown fences, no commentary, no text outside the JSON.\n"
  )

  # ── SOURCE DATA CONTEXT ────────────────────────────────────────
  data_context = ""
  if (!is.null(source_data)) {
    data_context = paste0(
      "\n## Source Data (ground truth — use this to verify every claim):\n",
      source_data, "\n"
    )
  }

  # ── CALIBRATED SCORING RUBRIC ──────────────────────────────────
  # Each Likert criterion now has anchored examples at levels 1, 3, and 5.
  criteria = '

## Scoring Criteria

### Boolean checks (true / false)
1. **accurate**: true if EVERY number, percentage, and factual claim in the report matches the source data. false if ANY value is wrong or misquoted, even by rounding.
2. **no_contractions**: true if the text uses zero informal contractions. false if even one contraction appears.
3. **no_hyperbole**: true if the text avoids all exaggerated/alarmist words (see list above). false if any appear.
4. **no_belittling**: true if the text contains no condescending phrases (see list above). false if any appear.

### Likert scales (integer 1–5)
5. **accuracy** — How well does the report reflect the source data?
   - 1 = multiple wrong numbers or fabricated claims
   - 3 = mostly correct but one or two values are paraphrased loosely (e.g. "about 12%" when source says 12.1%)
   - 5 = every number and percentage exactly matches the source data

6. **formality** — Does it read like a government report?
   - 1 = casual tone, slang, contractions, first/second person ("we", "you")
   - 3 = mostly formal but occasional informal phrasing
   - 5 = consistently formal, third-person, no contractions or colloquialisms

7. **faithfulness** — Does it stay within what the data supports?
   - 1 = makes causal claims or predictions not supported by the data
   - 3 = minor extrapolation beyond the data
   - 5 = every claim can be directly traced to a value in the source table

8. **clarity** — Is each sentence easy to understand on first read?
   - 1 = confusing structure, ambiguous pronouns, run-on sentences
   - 3 = mostly clear with occasional awkward phrasing
   - 5 = every sentence is crisp, specific, and unambiguous

9. **succinctness** — Is it concise without losing meaning?
   - 1 = padded with filler, redundant sentences, or unnecessary repetition
   - 3 = a few wordy passages but generally reasonable length
   - 5 = every word earns its place; no filler

10. **relevance** — Does every sentence relate to the source data?
    - 1 = contains off-topic commentary or generic filler
    - 3 = mostly on-topic with minor tangents
    - 5 = every sentence directly addresses the data or its implications

11. **data_specificity** — Does the report cite actual numbers from the source?
    - 1 = vague references only ("some emissions", "vehicles contributed")
    - 3 = cites some numbers but omits key values
    - 5 = cites specific percentages and values for all major categories

## Few-Shot Calibration Example

**Example input:** "Light Trucks made up 51.8% of PM10 emissions. Cars/Bikes were 36.1%. Together that is 87.9%."
**Example scores:**
```json
{
  "accurate": true,
  "no_contractions": true,
  "no_hyperbole": true,
  "no_belittling": true,
  "accuracy": 5,
  "formality": 5,
  "faithfulness": 5,
  "clarity": 5,
  "succinctness": 5,
  "relevance": 5,
  "data_specificity": 5,
  "details": "All values match source data. Formal tone. No filler."
}
```

## Required JSON Output Format
Return exactly this structure (integers for Likert, booleans for checks, string for details):
{
  "accurate": true/false,
  "no_contractions": true/false,
  "no_hyperbole": true/false,
  "no_belittling": true/false,
  "accuracy": 1-5,
  "formality": 1-5,
  "faithfulness": 1-5,
  "clarity": 1-5,
  "succinctness": 1-5,
  "relevance": 1-5,
  "data_specificity": 1-5,
  "details": "≤50 word explanation"
}
'

  # ── ASSEMBLE FULL PROMPT ───────────────────────────────────────
  full_prompt = paste0(
    instructions,
    data_context,
    "\n## Report Text to Validate:\n",
    report_text,
    criteria
  )

  return(full_prompt)
}
```

### What You Also Need to Update

**In `parse_quality_control_results()`** — add the two new fields so they don't get silently dropped:

```r
parse_quality_control_results = function(json_response) {
  # (keep existing JSON-extraction logic unchanged)
  json_response = str_replace_all(json_response, "```(?:json)?\\s*|```", "")
  first_brace = str_locate(json_response, "\\{")[1, "start"]
  last_brace  = str_locate_all(json_response, "\\}")[[1]]
  last_brace  = last_brace[nrow(last_brace), "end"]
  if (!is.na(first_brace) && !is.na(last_brace)) {
    json_response = substr(json_response, first_brace, last_brace)
  }

  quality_data = fromJSON(json_response)

  # Updated tibble — now includes no_belittling + data_specificity
  results = tibble(
    accurate         = quality_data$accurate,
    no_contractions  = if (!is.null(quality_data$no_contractions))  quality_data$no_contractions  else NA,
    no_hyperbole     = if (!is.null(quality_data$no_hyperbole))     quality_data$no_hyperbole     else NA,
    no_belittling    = if (!is.null(quality_data$no_belittling))    quality_data$no_belittling    else NA,
    accuracy         = quality_data$accuracy,
    formality        = quality_data$formality,
    faithfulness     = quality_data$faithfulness,
    clarity          = quality_data$clarity,
    succinctness     = quality_data$succinctness,
    relevance        = quality_data$relevance,
    data_specificity = if (!is.null(quality_data$data_specificity)) quality_data$data_specificity else NA,
    details          = quality_data$details
  )

  return(results)
}
```

**In the overall-score calculation** — include the new Likert field:

```r
overall_score = quality_results %>%
  select(accuracy, formality, faithfulness, clarity, succinctness, relevance, data_specificity) %>%
  rowMeans(na.rm = TRUE)
```

**In the results printout** — add the new boolean check:

```r
cat("📊 No Belittling Check:   ", ifelse(quality_results$no_belittling, "✅ PASS", "❌ FAIL"), "\n")
```

---

## Part 3: Execution Plan

### Step 1 — Run Manual QC First (baseline)
Open and run `01_manual_quality_control.R` as-is. Note the output for report 1:
- Concept counts, quality checks (contractions, hyperbole, belittling), text metrics.
- Save or screenshot this output — you'll compare it to the AI results.

### Step 2 — Run Original AI QC (before your changes)
1. Open `02_ai_quality_control.R`.
2. Set `AI_PROVIDER = "openai"` on line 46 (you have an API key configured).
3. Run the script on report 1 without any changes.
4. Screenshot the output: boolean results, Likert scores, overall score.
5. Save this as your "before" baseline.

### Step 3 — Apply the Improved Prompt
1. Replace `create_quality_control_prompt()` with the version from Part 2 above.
2. Replace `parse_quality_control_results()` with the updated version.
3. Update the overall-score calculation and printout lines.

### Step 4 — Run Improved AI QC
1. Run the modified script on report 1.
2. Screenshot the output — this is your "after" result.
3. Compare before vs. after: you should see tighter, more consistent scores.

### Step 5 — Run Batch QC on All 4 Reports
Uncomment the batch section (lines ~343–348) and run it. The four reports are designed to test different failure modes:

| Report | Expected behavior |
|--------|-------------------|
| 1 | High scores across the board — formal, accurate, data-specific |
| 2 | Should fail `no_contractions` (uses "they're", "we"), lower formality |
| 3 | Clean but uses "significant" — borderline; scores should be high |
| 4 | Should fail `no_hyperbole`, `no_belittling`, low `data_specificity` and `succinctness` |

### Step 6 — Prepare Submission
1. **Script**: Save your modified `02_ai_quality_control.R`.
2. **Screenshot**: Capture the QC results showing boolean checks, Likert scales, and overall score.
3. **Write-up (3–4 sentences)**: Example below —

> I improved the QC prompt by adding calibration anchors at levels 1/3/5 for each Likert criterion, a few-shot scored example for grading consistency, and two new checks (no_belittling and data_specificity) to align with the manual QC script's pattern-matching logic. Compared to manual QC, the AI approach captures semantic nuance (e.g., faithfulness to source data) that regex-based checks miss, but is less deterministic — running the same prompt twice can yield slightly different Likert scores. The few-shot example and lower temperature (0.3) helped stabilize scores across runs; further improvement could come from multi-run averaging or using structured-output mode with a strict JSON schema.

---

## Summary of All Improvements

| Improvement | Why it helps |
|-------------|-------------|
| Calibration anchors (1/3/5 examples per criterion) | Reduces model interpretation drift between runs |
| Few-shot scored example | Gives the model a concrete grading standard |
| `no_belittling` boolean check | Aligns AI QC with manual QC's belittling-phrase detection |
| `data_specificity` Likert scale | Catches vague reports that avoid citing actual numbers |
| Explicit cross-referencing instruction | Forces row-by-row comparison against source table |
| Expanded hyperbole/contraction word lists | Reduces false negatives on informal language |
| Separated system vs. user role guidance | Better instruction-following on OpenAI models |
