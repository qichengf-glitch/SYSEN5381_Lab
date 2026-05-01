# 03_statistical_comparison.R
# Statistical Comparison of Quality Control Scores Across Prompts
# Tim Fraser

# This script demonstrates how to use t-test and ANOVA to compare quality control
# scores for reports generated from different prompts. Students learn to perform
# statistical hypothesis testing to determine if prompt differences are significant.

# 0. SETUP ###################################

## 0.1 Load Packages #################################

# If you haven't already, install required packages:
# install.packages(c("dplyr", "broom", "readr"))

library(dplyr)  # for data wrangling
library(broom)  # for tidy statistical output
library(readr)  # for reading CSV files

## 0.2 Load Quality Control Scores ####################################

# If not launched via Rscript, walk up from cwd until we find `.git` (repo root).
find_project_root = function(start_dir = getwd()) {
  current = normalizePath(start_dir, winslash = "/", mustWork = FALSE)

  for (i in 1:50) {
    if (dir.exists(file.path(current, ".git"))) return(current)

    parent = normalizePath(file.path(current, ".."), winslash = "/", mustWork = FALSE)
    if (identical(parent, current)) break
    current = parent
  }

  normalizePath(start_dir, winslash = "/", mustWork = FALSE)
}

# Rscript passes `--file=/path/to/this_script.R`. Try that first, then repo-relative paths.
# Multiple candidates cover: any cwd, spaces in folder names, and interactive `source()`.
resolve_scores_csv_path = function() {
  fname = "prompt_comparison_scores.csv"
  candidates = character()

  args = commandArgs(trailingOnly = FALSE)
  file_arg = grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    raw = sub("^--file=", "", file_arg)
    if (nzchar(raw)) {
      # Some environments mangle spaces in paths (e.g. `Folder~+~Name`); try a de-mangled form.
      raw_alt = gsub("~\\+~", " ", raw, fixed = FALSE)
      for (r in unique(c(raw, raw_alt))) {
        if (!file.exists(r)) next
        candidates = c(
          candidates,
          file.path(dirname(normalizePath(r, winslash = "/", mustWork = TRUE)), "data", fname)
        )
      }
    }
  }

  candidates = c(
    candidates,
    file.path(find_project_root(), "09_text_analysis", "data", fname),
    file.path(getwd(), "09_text_analysis", "data", fname),
    file.path(getwd(), "data", fname)
  )

  for (p in candidates) {
    if (!nzchar(p)) next
    if (file.exists(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
    p2 = normalizePath(p, winslash = "/", mustWork = FALSE)
    if (file.exists(p2)) return(normalizePath(p2, winslash = "/", mustWork = TRUE))
  }

  NULL
}

scores_path = resolve_scores_csv_path()

# Load pre-computed quality control scores for reports from 3 different prompts
# Each prompt generated 30 reports, and each report was evaluated on multiple criteria
if (is.null(scores_path) || !file.exists(scores_path)) {
  stop(
    "Could not find `prompt_comparison_scores.csv`. Tried paths next to this script, ",
    "`09_text_analysis/data/` under the repo root and cwd, and `data/` under cwd."
  )
}
scores = read_csv(scores_path)

# View the data structure
cat("📊 Quality Control Scores Dataset:\n")
glimpse(scores)
cat("\n")

# 1. DESCRIPTIVE STATISTICS ###################################

## 1.1 Summary Statistics by Prompt #################################

# Calculate mean overall scores by prompt
# This gives us a first look at whether prompts differ in quality
summary_stats = scores %>%
  group_by(prompt_id) %>%
  reframe(
    mean_overall = mean(overall_score),
    sd_overall = sd(overall_score),
    mean_formality = mean(formality),
    mean_succinctness = mean(succinctness),
    mean_clarity = mean(clarity),
    n = n()
  )

cat("📈 Summary Statistics by Prompt:\n")
print(summary_stats)
cat("\n")

# Overall mean across all prompts
overall_mean = scores %>%
  reframe(mean = mean(overall_score))

cat("📊 Overall Mean Score (all prompts): ", round(overall_mean$mean, 2), "\n\n")

## 1.2 Visual Inspection #################################

# Create a simple boxplot to visualize score distributions
# This helps us see if there are obvious differences between prompts
cat("📊 Overall Score Distributions by Prompt:\n")
cat("   Prompt A: Mean = ", round(mean(scores$overall_score[scores$prompt_id == "A"]), 2), 
    ", SD = ", round(sd(scores$overall_score[scores$prompt_id == "A"]), 2), "\n")
cat("   Prompt B: Mean = ", round(mean(scores$overall_score[scores$prompt_id == "B"]), 2), 
    ", SD = ", round(sd(scores$overall_score[scores$prompt_id == "B"]), 2), "\n")
cat("   Prompt C: Mean = ", round(mean(scores$overall_score[scores$prompt_id == "C"]), 2), 
    ", SD = ", round(sd(scores$overall_score[scores$prompt_id == "C"]), 2), "\n\n")

# 2. TESTING ASSUMPTIONS ###################################

## 2.1 Homogeneity of Variance (Bartlett's Test) #################################

# Before running ANOVA, we need to check if the variances are equal across groups
# Bartlett's test checks whether the variances of our 3 groups are significantly different
bartlett_result = bartlett.test(formula = overall_score ~ prompt_id, data = scores)

cat("🔍 Bartlett's Test for Homogeneity of Variance:\n")
print(bartlett_result)
cat("\n")

# Interpret the result
# If p-value < 0.05, variances are significantly different (don't assume equal variance)
# If p-value >= 0.05, variances are not significantly different (can assume equal variance)
var_equal = bartlett_result$p.value >= 0.05
cat("📊 Equal Variance Assumption: ", ifelse(var_equal, "✅ Can assume equal variance", "❌ Do NOT assume equal variance"), "\n")
cat("   (p-value = ", round(bartlett_result$p.value, 4), ")\n\n")

# 3. TWO-GROUP COMPARISON: T-TEST ###################################

## 3.1 Compare Prompt A vs Prompt B #################################

# Extract scores for two prompts to compare
prompt_a_scores = scores %>% filter(prompt_id == "A") %>% pull(overall_score)
prompt_b_scores = scores %>% filter(prompt_id == "B") %>% pull(overall_score)

# Perform t-test
# This tests whether the mean scores differ significantly between Prompt A and Prompt B
t_test_result = t.test(prompt_a_scores, prompt_b_scores, var.equal = var_equal)

cat("📊 T-Test: Prompt A vs Prompt B\n")
cat("   Mean A: ", round(mean(prompt_a_scores), 2), "\n")
cat("   Mean B: ", round(mean(prompt_b_scores), 2), "\n")
cat("   Difference: ", round(mean(prompt_a_scores) - mean(prompt_b_scores), 2), "\n\n")

# Use broom::tidy() to get a clean table of results
t_test_tidy = broom::tidy(t_test_result)

cat("📋 T-Test Results (tidy format):\n")
print(t_test_tidy)
cat("\n")

# Interpret the result
cat("💡 Interpretation:\n")
if (t_test_tidy$p.value < 0.05) {
  cat("   ✅ The difference between Prompt A and Prompt B is statistically significant.\n")
  cat("   ✅ Prompt ", ifelse(mean(prompt_a_scores) > mean(prompt_b_scores), "A", "B"), 
      " performs significantly better (p = ", round(t_test_tidy$p.value, 4), ").\n")
} else {
  cat("   ❌ The difference between Prompt A and Prompt B is NOT statistically significant.\n")
  cat("   ❌ We cannot conclude that one prompt performs better than the other (p = ", 
      round(t_test_tidy$p.value, 4), ").\n")
}
cat("\n")

# 4. THREE-GROUP COMPARISON: ANOVA ###################################

## 4.1 One-Way ANOVA #################################

# Perform one-way ANOVA to compare all three prompts simultaneously
# This tests whether at least one prompt differs significantly from the others
# Use var.equal = FALSE if variances are not equal (Welch's ANOVA)
# Use var.equal = TRUE if variances are equal (standard ANOVA)
anova_result = oneway.test(formula = overall_score ~ prompt_id, data = scores, var.equal = var_equal)

cat("📊 ANOVA: Comparing All Three Prompts (A, B, C)\n")
print(anova_result)
cat("\n")

# Use broom::tidy() to get a clean table of results
anova_tidy = broom::tidy(anova_result)

cat("📋 ANOVA Results (tidy format):\n")
print(anova_tidy)
cat("\n")

# Extract F-statistic and p-value
f_statistic = anova_result$statistic
p_value = anova_result$p.value

cat("📊 F-statistic: ", round(f_statistic, 4), "\n")
cat("📊 p-value: ", round(p_value, 4), "\n\n")

## 4.2 Interpret ANOVA Results #################################

cat("💡 Interpretation:\n")
if (p_value < 0.05) {
  cat("   ✅ At least one prompt performs significantly differently from the others.\n")
  cat("   ✅ The F-statistic (", round(f_statistic, 4), ") is significant (p = ", 
      round(p_value, 4), ").\n")
  cat("   ✅ We can conclude that prompt choice significantly affects quality control scores.\n")
} else {
  cat("   ❌ We cannot conclude that prompts differ significantly.\n")
  cat("   ❌ The F-statistic (", round(f_statistic, 4), ") is not significant (p = ", 
      round(p_value, 4), ").\n")
  cat("   ❌ Prompt choice does not appear to significantly affect quality control scores.\n")
}
cat("\n")

# 5. COMPARING SPECIFIC QUALITY DIMENSIONS ###################################

## 5.1 Formality Comparison #################################

# Compare formality scores across prompts
# Prompt A should score higher on formality (formal writing style)
cat("📊 Formality Scores by Prompt:\n")
formality_stats = scores %>%
  group_by(prompt_id) %>%
  reframe(
    mean_formality = mean(formality),
    sd_formality = sd(formality)
  )
print(formality_stats)
cat("\n")

# ANOVA for formality
formality_anova = oneway.test(formula = formality ~ prompt_id, data = scores, var.equal = FALSE)
formality_anova_tidy = broom::tidy(formality_anova)

cat("📋 Formality ANOVA Results:\n")
print(formality_anova_tidy)
cat("\n")

## 5.2 Succinctness Comparison #################################

# Compare succinctness scores across prompts
# Prompt B should score higher on succinctness (concise writing)
cat("📊 Succinctness Scores by Prompt:\n")
succinctness_stats = scores %>%
  group_by(prompt_id) %>%
  reframe(
    mean_succinctness = mean(succinctness),
    sd_succinctness = sd(succinctness)
  )
print(succinctness_stats)
cat("\n")

# ANOVA for succinctness
succinctness_anova = oneway.test(formula = succinctness ~ prompt_id, data = scores, var.equal = FALSE)
succinctness_anova_tidy = broom::tidy(succinctness_anova)

cat("📋 Succinctness ANOVA Results:\n")
print(succinctness_anova_tidy)
cat("\n")

cat("✅ Statistical comparison complete!\n")
cat("💡 Key takeaway: Use these statistical tests to determine if prompt differences\n")
cat("   are statistically significant, not just due to random variation.\n")
