# hw3_validator.py
# HW3: AI Report Validation System
# SYSEN 5381 — Qicheng Fu
#
# Custom validation system for BDS (Business Dynamics Statistics) job-creation reports.
# Compares 3 report-generation prompts (A, B, C) using a tailored rubric,
# then runs one-way ANOVA to determine which prompt produces significantly better reports.
#
# Usage:
#   pip install openai pandas scipy pingouin matplotlib python-dotenv
#   python hw3_validator.py

# ── 0. SETUP ──────────────────────────────────────────────────────────────────

import os, json, re, time
import pandas as pd
from openai import OpenAI
from scipy.stats import bartlett
import pingouin as pg
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use("Agg")   # headless — no display needed
from dotenv import load_dotenv

# Load API key from dsai/.env (project convention)
_script_dir = os.path.dirname(os.path.abspath(__file__))
_repo_root = os.path.abspath(os.path.join(_script_dir, ".."))
for env_path in [
    os.path.join(_repo_root, "dsai", ".env"),
    os.path.join(_script_dir, ".env"),
    ".env",
]:
    if os.path.exists(env_path):
        load_dotenv(env_path)
        break

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL   = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

if not OPENAI_API_KEY:
    raise EnvironmentError("OPENAI_API_KEY not found. Check dsai/.env")

client = OpenAI(api_key=OPENAI_API_KEY)

# ── 1. SOURCE DATA ────────────────────────────────────────────────────────────
# Ground-truth context fed to both the reporter and the validator.

SOURCE_CONTEXT = """
Census Bureau — Business Dynamics Statistics (BDS)
Metric: JOB_CREATION | Geography: all 50 US states | Years: 2010-2023
Total clean rows: 714

National yearly job-creation totals:
  2010: 13,405,052
  2011: 14,728,007
  2012: 15,736,598
  2013: 15,522,990
  2014: 15,583,546
  2015: 16,279,659
  2016: 16,030,945
  2017: 17,102,443
  2018: 16,442,737
  2019: 15,803,545
  2020: 15,815,946
  2021: 15,068,762
  2022: 21,651,280   ← peak year
  2023: 18,450,128

Top 5 states by job creation in 2023 (FIPS → state):
  06 → California:  2,130,913
  48 → Texas:       1,792,537
  12 → Florida:     1,346,948
  36 → New York:    1,171,132
  17 → Illinois:      716,207
""".strip()

# ── 2. REPORT-GENERATION PROMPTS (A, B, C) ────────────────────────────────────
# Three prompts that differ in structure, role framing, and detail level.
# We test whether the prompt choice significantly affects report quality.

REPORT_PROMPTS = {
    "A": (
        "Summarize the following US job-creation data in 2-3 short paragraphs. "
        "Include the main trend and a few key numbers.\n\n"
        f"{SOURCE_CONTEXT}"
    ),
    "B": (
        "Write a structured government-style report on the following US job-creation data. "
        "Use three sections: (1) Overview, (2) Temporal Trends, (3) Regional Highlights. "
        "Cite specific figures in each section.\n\n"
        f"{SOURCE_CONTEXT}"
    ),
    "C": (
        "You are a senior economist at the U.S. Census Bureau. "
        "Write a formal analytical brief for a policy audience on the following job-creation data. "
        "The brief must: cite at least five specific figures, correctly identify the peak year, "
        "name the top three states in 2023, maintain formal third-person voice throughout, "
        "and make no claims beyond what the data directly supports.\n\n"
        f"{SOURCE_CONTEXT}"
    ),
}

# ── 3. CUSTOM VALIDATION RUBRIC ───────────────────────────────────────────────
# Dimensions are 0-100 percentage scores and boolean checks — NOT Likert 1-5 scales.
# Each dimension is calibrated specifically to BDS job-creation report evaluation.
#
# Dimension             | Type    | What it measures
# ─────────────────────────────────────────────────────────────────────────────
# data_specificity      | 0-100   | % of sentences that cite at least one numeric figure
# trend_correctness     | 0-100   | Accuracy in describing the 2010-2023 trend + peak year
# geographic_precision  | 0-100   | Correct identification of top states and their values
# factual_accuracy      | boolean | TRUE if every cited number is within 5% of source value
# formality_score       | 0-100   | Professional, third-person, no contractions or hyperbole
# no_fabrication        | boolean | TRUE if no claim is made about data not present in source

VALIDATION_SYSTEM_PROMPT = """
You are a strict quality-control validator for Census Bureau economic reports.
You will receive a report and the source data it should be based on.
Score the report on every criterion below and return ONLY valid JSON — no markdown, no commentary.

Scoring dimensions:

1. data_specificity (integer 0-100):
   Count sentences that contain at least one specific numeric figure (e.g., "2,130,913" or "21.6 million").
   Score = (sentences_with_numbers / total_sentences) × 100, rounded to nearest integer.
   - 0  = no numbers cited at all
   - 50 = roughly half of sentences contain figures
   - 100 = every sentence references a specific number

2. trend_correctness (integer 0-100):
   Does the report correctly describe the national trend from 2010-2023?
   - Must identify 2022 as the peak year (21,651,280) to score above 60.
   - Must note the post-2022 decline to score above 80.
   - Must mention growth from 2010 to score above 40.
   Score calibration: 0=completely wrong trend, 50=partial, 100=fully accurate trend narrative.

3. geographic_precision (integer 0-100):
   Does the report correctly name leading states?
   - +20 pts each for correctly naming California, Texas, Florida, New York, Illinois as top states.
   - Deduct 20 pts for each wrong state listed as a top state.
   - Cap at 0 minimum, 100 maximum.

4. factual_accuracy (boolean true/false):
   true = every cited number is within 5% of the correct value in the source data.
   false = at least one cited number deviates by more than 5% from source data.

5. formality_score (integer 0-100):
   - 0  = casual, first-person, contractions, slang
   - 50 = mostly formal but some informal phrasing or second-person voice
   - 100 = fully formal, third-person, no contractions, no hyperbole, no filler phrases

6. no_fabrication (boolean true/false):
   true = every claim can be traced to a value in the source data (no invented statistics).
   false = report contains at least one number or claim not present in the source data.

Return exactly this JSON structure:
{
  "data_specificity": <0-100>,
  "trend_correctness": <0-100>,
  "geographic_precision": <0-100>,
  "factual_accuracy": <true|false>,
  "formality_score": <0-100>,
  "no_fabrication": <true|false>,
  "rationale": "<30-50 word explanation of your scores>"
}
""".strip()

# ── 4. HELPER FUNCTIONS ───────────────────────────────────────────────────────

def generate_report(prompt: str, attempt: int = 0) -> str:
    """Call OpenAI to generate a BDS report from the given prompt."""
    try:
        resp = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.8,   # some variation so repeated runs differ
            max_tokens=600,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        if attempt < 2:
            time.sleep(3)
            return generate_report(prompt, attempt + 1)
        raise e


def validate_report(report_text: str, attempt: int = 0) -> dict:
    """Call OpenAI to validate a report and return scored dimensions as a dict."""
    user_msg = (
        f"SOURCE DATA:\n{SOURCE_CONTEXT}\n\n"
        f"REPORT TO VALIDATE:\n{report_text}"
    )
    try:
        resp = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": VALIDATION_SYSTEM_PROMPT},
                {"role": "user",   "content": user_msg},
            ],
            temperature=0.1,   # low temp for consistent scoring
            max_tokens=400,
        )
        raw = resp.choices[0].message.content.strip()
        # Strip markdown fences if present
        raw = re.sub(r"```(?:json)?", "", raw).strip().rstrip("`").strip()
        return json.loads(raw)
    except json.JSONDecodeError:
        if attempt < 2:
            time.sleep(2)
            return validate_report(report_text, attempt + 1)
        print(f"  ⚠ JSON parse failed after retries. Raw: {raw[:120]}")
        return {}
    except Exception as e:
        if attempt < 2:
            time.sleep(3)
            return validate_report(report_text, attempt + 1)
        raise e


def compute_overall_score(row: dict) -> float:
    """
    Aggregate the six dimensions into a single 0-100 overall score.
    Weights reflect the rubric's emphasis on accuracy and data citation.
    """
    # Convert booleans to 0/100
    fa = 100 if row.get("factual_accuracy", False) else 0
    nf = 100 if row.get("no_fabrication",  True)  else 0

    weighted = (
        row.get("data_specificity",     0) * 0.20 +
        row.get("trend_correctness",    0) * 0.25 +
        row.get("geographic_precision", 0) * 0.20 +
        fa                                * 0.15 +
        row.get("formality_score",      0) * 0.10 +
        nf                                * 0.10
    )
    return round(weighted, 2)


# ── 5. EXPERIMENT ─────────────────────────────────────────────────────────────

REPORTS_PER_PROMPT = 12   # 12 × 3 prompts = 36 total API calls for generation
                           # + 36 validation calls = 72 total calls

print("=" * 60)
print("HW3 — BDS Report Validation Experiment")
print(f"Model: {OPENAI_MODEL}  |  Reports per prompt: {REPORTS_PER_PROMPT}")
print("=" * 60)

records = []

for prompt_id, prompt_text in REPORT_PROMPTS.items():
    print(f"\n📝 Prompt {prompt_id}: generating {REPORTS_PER_PROMPT} reports...")
    for i in range(1, REPORTS_PER_PROMPT + 1):
        print(f"  [{i}/{REPORTS_PER_PROMPT}] generating...", end=" ", flush=True)
        report = generate_report(prompt_text)

        print("validating...", end=" ", flush=True)
        scores = validate_report(report)

        if not scores:
            print("⚠ skip (parse error)")
            continue

        row = {
            "prompt_id":            prompt_id,
            "run":                  i,
            "data_specificity":     scores.get("data_specificity",     0),
            "trend_correctness":    scores.get("trend_correctness",    0),
            "geographic_precision": scores.get("geographic_precision", 0),
            "factual_accuracy":     1 if scores.get("factual_accuracy", False) else 0,
            "formality_score":      scores.get("formality_score",      0),
            "no_fabrication":       1 if scores.get("no_fabrication",  True)  else 0,
            "rationale":            scores.get("rationale", ""),
            "report_snippet":       report[:200],
        }
        row["overall_score"] = compute_overall_score(row)
        records.append(row)
        print(f"✅ overall={row['overall_score']:.1f}")

        time.sleep(0.5)   # gentle rate limiting

# ── 6. SAVE RESULTS ───────────────────────────────────────────────────────────

df = pd.DataFrame(records)
out_dir = "11_decision_support"
os.makedirs(out_dir, exist_ok=True)

csv_path = os.path.join(out_dir, "hw3_validation_scores.csv")
df.to_csv(csv_path, index=False)
print(f"\n💾 Scores saved → {csv_path}")

# ── 7. DESCRIPTIVE STATISTICS ─────────────────────────────────────────────────

print("\n" + "=" * 60)
print("DESCRIPTIVE STATISTICS")
print("=" * 60)

summary = df.groupby("prompt_id")["overall_score"].agg(
    n="count", mean="mean", std="std", min="min", max="max"
).round(2)
print(summary.to_string())

for pid in ["A", "B", "C"]:
    sub = df[df.prompt_id == pid]["overall_score"]
    print(f"\nPrompt {pid}: mean={sub.mean():.2f}  std={sub.std():.2f}  n={len(sub)}")

# ── 8. STATISTICAL ANALYSIS: ANOVA ────────────────────────────────────────────

print("\n" + "=" * 60)
print("STATISTICAL ANALYSIS")
print("=" * 60)

a = df[df.prompt_id == "A"]["overall_score"]
b = df[df.prompt_id == "B"]["overall_score"]
c = df[df.prompt_id == "C"]["overall_score"]

# Bartlett's test for homogeneity of variance
b_stat, b_p = bartlett(a, b, c)
var_equal = b_p >= 0.05
print(f"\nBartlett's test: statistic={b_stat:.4f}  p={b_p:.4f}")
print(f"Equal variance assumption: {'✅ YES' if var_equal else '❌ NO (use Welch)'}")

# One-way ANOVA (or Welch's ANOVA)
if var_equal:
    anova_result = pg.anova(dv="overall_score", between="prompt_id", data=df)
    print("\n📊 One-Way ANOVA:")
else:
    anova_result = pg.welch_anova(dv="overall_score", between="prompt_id", data=df)
    print("\n📊 Welch's ANOVA:")
print(anova_result.to_string())

f_stat = anova_result["F"].values[0]
p_val  = anova_result["p_unc"].values[0]
print(f"\nF = {f_stat:.4f},  p = {p_val:.4f}")

if p_val < 0.05:
    best = df.groupby("prompt_id")["overall_score"].mean().idxmax()
    print(f"✅ Significant difference found (p < 0.05). Prompt {best} performs best.")
else:
    print("❌ No significant difference between prompts (p ≥ 0.05).")

# Post-hoc pairwise t-tests
print("\n📊 Pairwise T-Tests (Bonferroni corrected):")
posthoc = pg.pairwise_tests(dv="overall_score", between="prompt_id",
                             data=df, padjust="bonferroni")
print(posthoc[["A", "B", "T", "dof", "p_unc", "p_corr"]].to_string())

# ── 9. VISUALISATION ──────────────────────────────────────────────────────────

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

# Boxplot
colors = {"A": "#4C72B0", "B": "#DD8452", "C": "#55A868"}
groups = [df[df.prompt_id == p]["overall_score"].values for p in ["A", "B", "C"]]
bp = axes[0].boxplot(groups, patch_artist=True, labels=["Prompt A", "Prompt B", "Prompt C"])
for patch, color in zip(bp["boxes"], colors.values()):
    patch.set_facecolor(color)
axes[0].set_title("Overall Score Distribution by Prompt", fontsize=13)
axes[0].set_ylabel("Overall Score (0–100)")
axes[0].set_xlabel("Prompt")

# Mean ± SD bar chart per dimension
dims = ["data_specificity", "trend_correctness", "geographic_precision",
        "formality_score"]
dim_means = df.groupby("prompt_id")[dims].mean()
dim_stds  = df.groupby("prompt_id")[dims].std()

x = range(len(dims))
width = 0.25
for idx, (pid, color) in enumerate(colors.items()):
    offset = (idx - 1) * width
    axes[1].bar([xi + offset for xi in x],
                dim_means.loc[pid], width,
                yerr=dim_stds.loc[pid],
                label=f"Prompt {pid}", color=color, alpha=0.85,
                capsize=4)

axes[1].set_xticks(list(x))
axes[1].set_xticklabels(["Data\nSpecificity", "Trend\nCorrectness",
                          "Geo\nPrecision", "Formality"], fontsize=9)
axes[1].set_title("Mean Score per Dimension by Prompt", fontsize=13)
axes[1].set_ylabel("Score (0–100)")
axes[1].legend()

plt.tight_layout()
fig_path = os.path.join(out_dir, "hw3_score_comparison.png")
plt.savefig(fig_path, dpi=150)
print(f"\n📊 Chart saved → {fig_path}")

# ── 10. SAMPLE OUTPUTS ────────────────────────────────────────────────────────

print("\n" + "=" * 60)
print("SAMPLE VALIDATION OUTPUT (first record per prompt)")
print("=" * 60)
for pid in ["A", "B", "C"]:
    row = df[df.prompt_id == pid].iloc[0]
    print(f"\n── Prompt {pid} (overall={row['overall_score']}) ──")
    print(f"  data_specificity    : {row['data_specificity']}")
    print(f"  trend_correctness   : {row['trend_correctness']}")
    print(f"  geographic_precision: {row['geographic_precision']}")
    print(f"  factual_accuracy    : {bool(row['factual_accuracy'])}")
    print(f"  formality_score     : {row['formality_score']}")
    print(f"  no_fabrication      : {bool(row['no_fabrication'])}")
    print(f"  rationale: {row['rationale']}")

print("\n✅ hw3_validator.py complete.")
print(f"   CSV  → {csv_path}")
print(f"   Plot → {fig_path}")
