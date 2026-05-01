# 02_ai_quality_control.R
# AI-Assisted Text Quality Control
# Tim Fraser

# This script demonstrates how to use AI (Ollama or OpenAI) to perform quality control
# on AI-generated text reports. It implements quality control criteria including
# boolean accuracy checks and Likert scales for multiple quality dimensions.
# Students learn to design quality control prompts and structure AI outputs as JSON.

# 0. SETUP ###################################

## 0.1 Load Packages #################################

# If you haven't already, install required packages:
# install.packages(c("dplyr", "stringr", "readr", "httr2", "jsonlite"))

library(dplyr)    # for data wrangling
library(stringr)  # for text processing
library(readr)    # for reading files
library(httr2)    # for HTTP requests
library(jsonlite) # for JSON operations

## 0.2 Project root & environment ####################################

# Locate project root first so .env and data paths work from any working directory
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

project_root = find_project_root()
env_path = file.path(project_root, ".env")
if (file.exists(env_path)) {
  readRenviron(env_path)
}

## 0.3 Configuration ####################################

# Choose your AI provider: "ollama" or "openai"
AI_PROVIDER = "openai"  # Use OpenAI for the lab workflow; switch to "ollama" for local models

# Ollama: default model should be one you have installed (`ollama list`).
# Ollama returns HTTP 404 if the model name is missing — e.g. pull with: ollama pull llama3.2
PORT = 11434
OLLAMA_HOST = paste0("http://localhost:", PORT)
OLLAMA_MODEL = Sys.getenv("OLLAMA_MODEL", "smollm2:1.7b")

# OpenAI configuration (needs OPENAI_API_KEY in .env at project root)
if (AI_PROVIDER == "openai" && !file.exists(env_path)) {
  warning(".env not found at project root (", env_path, "). Create it with OPENAI_API_KEY=... for OpenAI.")
}
OPENAI_API_KEY = Sys.getenv("OPENAI_API_KEY")
OPENAI_MODEL = "gpt-4o-mini"  # Low-cost model

## 0.4 Load Sample Data ####################################
sample_reports_path = file.path(project_root, "09_text_analysis", "data", "sample_reports.txt")

# Load sample report text for quality control
sample_text = read_file(sample_reports_path)
reports = strsplit(sample_text, "\n\n")[[1]]
reports = trimws(reports)
reports = reports[reports != ""]  # Remove empty strings
report = reports[1]

# Load source data (if available) for accuracy checking
# In this example, we'll use a simple data structure
source_data = "White County, IL | 2015 | PM10 | Time Driven | hours
|type        |label_value |label_percent |
|:-----------|:-----------|:-------------|
|Light Truck |2.7 M       |51.8%         |
|Car/ Bike   |1.9 M       |36.1%         |
|Combo Truck |381.3 k     |7.3%          |
|Heavy Truck |220.7 k     |4.2%          |
|Bus         |30.6 k      |0.6%          |"

cat("📝 Report for Quality Control:\n")
cat("---\n")
cat(report)
cat("\n---\n\n")

# 1. AI QUALITY CONTROL FUNCTION ###################################

## 1.1 Create Quality Control Prompt #################################

# Shared system instructions so chat-based models get the grading policy in the system role.
create_quality_control_system_message = function() {
  paste0(
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
}

# Create a comprehensive quality control prompt based on samplevalidation.tex
# This prompt asks the AI to evaluate text on multiple criteria
create_quality_control_prompt = function(report_text, source_data = NULL) {

  # System-level instructions are duplicated in the prompt so providers without a
  # dedicated system role still receive the full grading policy.
  instructions = create_quality_control_system_message()

  # Add source data if provided for accuracy checking
  data_context = ""
  if (!is.null(source_data)) {
    data_context = paste0(
      "\n## Source Data (ground truth - use this to verify every claim):\n",
      source_data, "\n"
    )
  }

  # Each Likert criterion now has anchored examples at levels 1, 3, and 5.
  criteria = '

## Scoring Criteria

### Boolean checks (true / false)
1. **accurate**: true if EVERY number, percentage, and factual claim in the report matches the source data. false if ANY value is wrong or misquoted, even by rounding.
2. **no_contractions**: true if the text uses zero informal contractions. false if even one contraction appears.
3. **no_hyperbole**: true if the text avoids all exaggerated/alarmist words (see list above). false if any appear.
4. **no_belittling**: true if the text contains no condescending phrases (see list above). false if any appear.

### Likert scales (integer 1-5)
5. **accuracy** - How well does the report reflect the source data?
   - 1 = multiple wrong numbers or fabricated claims
   - 3 = mostly correct but one or two values are paraphrased loosely (e.g. "about 12%" when source says 12.1%)
   - 5 = every number and percentage exactly matches the source data

6. **formality** - Does it read like a government report?
   - 1 = casual tone, slang, contractions, first/second person ("we", "you")
   - 3 = mostly formal but occasional informal phrasing
   - 5 = consistently formal, third-person, no contractions or colloquialisms

7. **faithfulness** - Does it stay within what the data supports?
   - 1 = makes causal claims or predictions not supported by the data
   - 3 = minor extrapolation beyond the data
   - 5 = every claim can be directly traced to a value in the source table

8. **clarity** - Is each sentence easy to understand on first read?
   - 1 = confusing structure, ambiguous pronouns, run-on sentences
   - 3 = mostly clear with occasional awkward phrasing
   - 5 = every sentence is crisp, specific, and unambiguous

9. **succinctness** - Is it concise without losing meaning?
   - 1 = padded with filler, redundant sentences, or unnecessary repetition
   - 3 = a few wordy passages but generally reasonable length
   - 5 = every word earns its place; no filler

10. **relevance** - Does every sentence relate to the source data?
    - 1 = contains off-topic commentary or generic filler
    - 3 = mostly on-topic with minor tangents
    - 5 = every sentence directly addresses the data or its implications

11. **data_specificity** - Does the report cite actual numbers from the source?
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
  "details": "<=50 word explanation"
}
'

  # Combine into full prompt
  full_prompt = paste0(
    instructions,
    data_context,
    "\n## Report Text to Validate:\n",
    report_text,
    criteria
  )

  return(full_prompt)
}

## 1.2 Query AI Function #################################

# Function to query AI and get quality control results
query_ai_quality_control = function(prompt, provider = AI_PROVIDER) {
  system_message = create_quality_control_system_message()

  if (provider == "ollama") {
    # Query Ollama
    url = paste0(OLLAMA_HOST, "/api/chat")

    body = list(
      model = OLLAMA_MODEL,
      messages = list(
        list(
          role = "system",
          content = system_message
        ),
        list(
          role = "user",
          content = prompt
        )
      ),
      format = "json",  # Request JSON output
      stream = FALSE
    )
    
    res = request(url) %>%
      req_body_json(body) %>%
      req_method("POST") %>%
      req_perform()
    
    response = resp_body_json(res)
    output = response$message$content
    
  } else if (provider == "openai") {
    # Query OpenAI
    if (OPENAI_API_KEY == "") {
      stop("OPENAI_API_KEY not found in .env file. Please set it up first.")
    }
    
    url = "https://api.openai.com/v1/chat/completions"
    
    body = list(
      model = OPENAI_MODEL,
      messages = list(
        list(
          role = "system",
          content = system_message
        ),
        list(
          role = "user",
          content = prompt
        )
      ),
      response_format = list(type = "json_object"),  # Request JSON output
      temperature = 0.3  # Lower temperature for more consistent validation
    )
    
    res = request(url) %>%
      req_headers(
        "Authorization" = paste0("Bearer ", OPENAI_API_KEY),
        "Content-Type" = "application/json"
      ) %>%
      req_body_json(body) %>%
      req_method("POST") %>%
      req_perform()
    
    response = resp_body_json(res)
    output = response$choices[[1]]$message$content
    
  } else {
    stop("Invalid provider. Use 'ollama' or 'openai'.")
  }
  
  return(output)
}

## 1.3 Parse Quality Control Results #################################

# Parse JSON response and convert to tibble
parse_quality_control_results = function(json_response) {
  # Strip markdown code fences if present (e.g. ```json ... ```)
  json_response = str_replace_all(json_response, "```(?:json)?\\s*|```", "")

  # Extract the JSON object — use a greedy multiline match between first { and last }
  first_brace = str_locate(json_response, "\\{")[1, "start"]
  last_brace  = str_locate_all(json_response, "\\}")[[1]]
  last_brace  = last_brace[nrow(last_brace), "end"]
  if (!is.na(first_brace) && !is.na(last_brace)) {
    json_response = substr(json_response, first_brace, last_brace)
  }

  # Parse JSON
  quality_data = fromJSON(json_response)

  # Convert to tibble — include new boolean fields (fall back to NA if absent)
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

# 2. RUN QUALITY CONTROL ###################################

## 2.1 Create Quality Control Prompt #################################

quality_prompt = create_quality_control_prompt(report, source_data)

cat("🤖 Querying AI for quality control...\n\n")

## 2.2 Query AI #################################

ai_response = query_ai_quality_control(quality_prompt, provider = AI_PROVIDER)

cat("📥 AI Response (raw):\n")
cat(ai_response)
cat("\n\n")

## 2.3 Parse and Display Results #################################

quality_results = parse_quality_control_results(ai_response)

cat("✅ Quality Control Results:\n")
print(quality_results)
cat("\n")

## 2.4 Calculate Overall Score #################################

# Calculate average Likert score (excluding boolean checks)
overall_score = quality_results %>%
  select(accuracy, formality, faithfulness, clarity, succinctness, relevance, data_specificity) %>%
  rowMeans(na.rm = TRUE)

quality_results = quality_results %>%
  mutate(overall_score = round(overall_score, 2))

cat("📊 Overall Quality Score (average of Likert scales): ", overall_score, "/ 5.0\n")
cat("📊 Accuracy Check:        ", ifelse(quality_results$accurate,        "✅ PASS", "❌ FAIL"), "\n")
cat("📊 No Contractions Check: ", ifelse(quality_results$no_contractions, "✅ PASS", "❌ FAIL"), "\n")
cat("📊 No Hyperbole Check:    ", ifelse(quality_results$no_hyperbole,    "✅ PASS", "❌ FAIL"), "\n")
cat("📊 No Belittling Check:   ", ifelse(quality_results$no_belittling,   "✅ PASS", "❌ FAIL"), "\n\n")

# 3. QUALITY CONTROL MULTIPLE REPORTS ###################################

## 3.1 Batch Quality Control Function #################################

# Function to check multiple reports
check_multiple_reports = function(reports, source_data = NULL) {
  
  cat("🔄 Performing quality control on ", length(reports), " reports...\n\n")
  
  all_results = list()
  
  for (i in 1:length(reports)) {
    cat("Checking report ", i, " of ", length(reports), "...\n")
    
    # Create prompt
    prompt = create_quality_control_prompt(reports[i], source_data)
    
    # Query AI
    tryCatch({
      response = query_ai_quality_control(prompt, provider = AI_PROVIDER)
      results = parse_quality_control_results(response)
      results = results %>% mutate(report_id = i)
      all_results[[i]] = results
    }, error = function(e) {
      cat("❌ Error checking report ", i, ": ", e$message, "\n")
    })
    
    # Small delay to avoid rate limiting
    Sys.sleep(1)
  }
  
  # Combine all results
  combined_results = bind_rows(all_results)
  
  return(combined_results)
}

## 3.2 Run Batch Quality Control (Optional) #################################

# Uncomment to check all reports
# if (length(reports) > 1) {
#   batch_results = check_multiple_reports(reports, source_data)
#   cat("\n📊 Batch Quality Control Results:\n")
#   print(batch_results)
# }

cat("✅ AI quality control complete!\n")
cat("💡 Compare these results with manual quality control (01_manual_quality_control.R) to see how AI performs.\n")
