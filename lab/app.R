# AI-Powered Reporter Software (SYSEN 5381 Lab)
# How to run:
#   shiny::runApp("lab")
# API key setup:
#   Census (optional but recommended): Sys.setenv(CENSUS_API_KEY = "...")
#   OR put in .Renviron file in project root or home directory
# AI setup:
#   OpenAI: Sys.setenv(OPENAI_API_KEY = "...", OPENAI_MODEL = "gpt-4o-mini")
#   OR Ollama: Sys.setenv(OLLAMA_MODEL = "smollm2:1.7b", OLLAMA_HOST = "http://localhost:11434")

# Load environment variables from .Renviron and .env files
# Try multiple locations in order of preference
renv_paths = c(
  ".Renviron",                    # Current directory (lab/)
  "../dsai/.Renviron",            # Parent dsai directory
  "../../dsai/.Renviron",          # Two levels up
  "~/.Renviron"                   # Home directory
)
for (path in renv_paths) {
  if (file.exists(path)) {
    readRenviron(path)
    break
  }
}

# Also try to load from .env files (for Python-style projects)
env_paths = c(
  "../dsai/.env",                 # Parent dsai directory
  "../../dsai/.env",              # Two levels up
  ".env"                          # Current directory
)
for (path in env_paths) {
  if (file.exists(path)) {
    env_lines = readLines(path, warn = FALSE)
    for (line in env_lines) {
      line = trimws(line)
      if (nchar(line) > 0 && !startsWith(line, "#") && grepl("=", line)) {
        parts = strsplit(line, "=", fixed = TRUE)[[1]]
        if (length(parts) == 2) {
          key = trimws(parts[1])
          value = trimws(parts[2])
          # Only set if not already set
          if (!nzchar(Sys.getenv(key))) {
            do.call(Sys.setenv, setNames(list(value), key))
          }
        }
      }
    }
    break
  }
}

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(lubridate)
  library(glue)
  library(stringr)
  library(httr2)
  library(jsonlite)
})

source("mrts_helpers.R")

# ── AI Quality Control helpers (adapted from 09_text_analysis/02_ai_quality_control.R) ──

create_qc_prompt = function(report_text, source_data = NULL) {
  instructions = "You are a strict quality control validator for AI-generated government reports. Evaluate the following report text on multiple criteria. Be critical and consistent. Return ONLY valid JSON — no prose, no markdown fences, no extra text before or after the JSON object."
  data_context = if (!is.null(source_data)) paste0("\n\nSource Data:\n", source_data, "\n") else ""
  criteria = '

Quality Control Criteria:

1. **accurate** (boolean): TRUE if the paragraph contains no factual misinterpretation of the supplied data. FALSE if any numbers, percentages, or conclusions are wrong.

2. **no_contractions** (boolean): TRUE if the paragraph contains NO informal contractions (e.g. "we\'re", "they\'re", "it\'s", "can\'t"). FALSE if any contractions appear.

3. **no_hyperbole** (boolean): TRUE if the paragraph avoids exaggerated or alarmist language (e.g. "crucial", "critical", "absolutely essential", "obviously"). FALSE if any such language appears.

4. **accuracy** (integer 1-5): 1 = multiple errors interpreting the data, 5 = perfectly accurate.

5. **formality** (integer 1-5): 1 = casual/conversational tone, 5 = formal government-report style.

6. **faithfulness** (integer 1-5): 1 = claims far beyond data, 5 = claims strictly grounded in data.

7. **clarity** (integer 1-5): 1 = confusing phrasing, 5 = every sentence is clear and unambiguous.

8. **succinctness** (integer 1-5): 1 = padded with unnecessary words, 5 = concise and to the point.

9. **relevance** (integer 1-5): 1 = off-topic commentary, 5 = every sentence is directly relevant.

Return ONLY this JSON object:
{
  "accurate": true/false,
  "no_contractions": true/false,
  "no_hyperbole": true/false,
  "accuracy": 1-5,
  "formality": 1-5,
  "faithfulness": 1-5,
  "clarity": 1-5,
  "succinctness": 1-5,
  "relevance": 1-5,
  "details": "0-50 word explanation"
}
'
  paste0(instructions, data_context, "\n\nReport Text to Validate:\n", report_text, criteria)
}

# httr2/cli decorate errors with ANSI sequences; browsers show garbage like "[1m [22m"
strip_cli_ansi = function(x) {
  x = as.character(x)
  x = gsub("\033\\[[0-9;]*m", "", x, perl = TRUE)
  gsub("\001\\[[0-9;]*m", "", x, perl = TRUE)
}

# OpenAI rejects the whole request if JSON is malformed — often caused by invalid UTF-8,
# NUL bytes, or stray C0 control characters inside Agent 3 markdown.
sanitize_chat_text = function(x) {
  x = paste(as.character(x), collapse = "\n")
  x = iconv(x, to = "UTF-8", sub = " ")
  if (length(x) != 1L) x = paste(x, collapse = "\n")
  Encoding(x) = "UTF-8"
  ints = tryCatch(
    utf8ToInt(x),
    error = function(e) utf8ToInt(iconv(x, to = "UTF-8", sub = " "))
  )
  keep = ints == 9L | ints == 10L | ints >= 32L
  intToUtf8(ints[keep])
}

openai_chat_completions_json = function(model, system_content, user_content, temperature = 0.3) {
  payload = list(
    model = trimws(as.character(model)[1]),
    messages = list(
      list(role = "system", content = sanitize_chat_text(system_content)),
      list(role = "user", content = sanitize_chat_text(user_content))
    ),
    temperature = as.numeric(temperature)[1]
  )
  json = as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null"))
  charToRaw(enc2utf8(json))
}

http_resp_error_detail = function(resp) {
  raw_txt = tryCatch(resp_body_string(resp), error = function(e) "")
  parsed = tryCatch(jsonlite::fromJSON(raw_txt, simplifyVector = TRUE), error = function(e) NULL)
  if (is.list(parsed) && !is.null(parsed$error)) {
    err = parsed$error
    if (is.character(err)) return(paste(err, collapse = " "))
    if (is.list(err) && !is.null(err$message)) return(as.character(err$message))
  }
  if (nzchar(raw_txt)) return(substr(raw_txt, 1, 500))
  paste("HTTP", resp_status(resp))
}

# .env often sets OLLAMA_HOST=FALSE meaning "unset"; nzchar("FALSE") is TRUE → curl tries host "FALSE"
is_env_placeholder = function(x) {
  if (length(x) != 1L) return(TRUE)
  t = tolower(trimws(as.character(x)))
  !nzchar(t) || t %in% c("false", "true", "na", "0", "no", "off", "none", "null", "nil")
}

normalize_ollama_base_url = function(host, default = "http://localhost:11434") {
  if (is.logical(host)) return(default)
  h = trimws(paste(as.character(host), collapse = ""))
  if (is_env_placeholder(h)) return(default)
  if (!grepl("^https?://", h, ignore.case = TRUE)) h = paste0("http://", h)
  sub("/$", "", h)
}

normalize_ollama_model_name = function(model, default = "smollm2:1.7b") {
  m = trimws(paste(as.character(model), collapse = ""))
  if (is_env_placeholder(m)) return(default)
  m
}

normalize_openai_model_name = function(model, default = "gpt-4o-mini") {
  m = trimws(paste(as.character(model), collapse = ""))
  if (is_env_placeholder(m)) return(default)
  m
}

query_ai_qc = function(prompt, provider, ollama_host, ollama_model, openai_key, openai_model) {
  if (provider == "ollama") {
    base = normalize_ollama_base_url(ollama_host)
    model_use = normalize_ollama_model_name(ollama_model)
    body = list(
      model = model_use,
      messages = list(list(role = "user", content = sanitize_chat_text(prompt))),
      format = "json",
      stream = FALSE
    )
    resp = tryCatch(
      request(paste0(base, "/api/chat")) |>
        req_body_json(body) |>
        req_method("POST") |>
        req_error(is_error = function(resp) FALSE) |>
        req_perform(),
      error = function(e) stop(strip_cli_ansi(conditionMessage(e)))
    )
    if (resp_status(resp) != 200L) {
      stop(strip_cli_ansi(glue("Ollama HTTP {resp_status(resp)}: {http_resp_error_detail(resp)}")))
    }
    resp_body_json(resp)$message$content
  } else {
    if (!nzchar(openai_key)) stop("OPENAI_API_KEY not configured.")
    # Do not use response_format=json_object: many model names / endpoints return HTTP 400.
    # The prompt already requires JSON; parse_qc_results() tolerates fences and extra text.
    # Build JSON explicitly (UTF-8 raw body) so markdown from Agent 3 cannot break serialization.
    sys_msg = "You are a quality control validator. Reply with one JSON object only. No markdown code fences."
    json_raw = openai_chat_completions_json(
      normalize_openai_model_name(openai_model),
      sys_msg,
      prompt,
      0.3
    )
    resp = tryCatch(
      request("https://api.openai.com/v1/chat/completions") |>
        req_headers(
          "Authorization" = paste0("Bearer ", openai_key),
          "Content-Type" = "application/json; charset=utf-8"
        ) |>
        req_body_raw(json_raw) |>
        req_method("POST") |>
        req_error(is_error = function(resp) FALSE) |>
        req_perform(),
      error = function(e) stop(strip_cli_ansi(conditionMessage(e)))
    )
    if (resp_status(resp) != 200L) {
      stop(strip_cli_ansi(glue("OpenAI HTTP {resp_status(resp)}: {http_resp_error_detail(resp)}")))
    }
    resp_body_json(resp)$choices[[1]]$message$content
  }
}

parse_qc_results = function(json_response) {
  json_response = str_replace_all(json_response, "```(?:json)?\\s*|```", "")
  first_brace = str_locate(json_response, "\\{")[1, "start"]
  last_brace  = str_locate_all(json_response, "\\}")[[1]]
  last_brace  = last_brace[nrow(last_brace), "end"]
  if (!is.na(first_brace) && !is.na(last_brace)) {
    json_response = substr(json_response, first_brace, last_brace)
  }
  d = fromJSON(json_response)
  list(
    accurate        = isTRUE(d$accurate),
    no_contractions = if (!is.null(d$no_contractions)) isTRUE(d$no_contractions) else NA,
    no_hyperbole    = if (!is.null(d$no_hyperbole))    isTRUE(d$no_hyperbole)    else NA,
    accuracy        = as.integer(d$accuracy),
    formality       = as.integer(d$formality),
    faithfulness    = as.integer(d$faithfulness),
    clarity         = as.integer(d$clarity),
    succinctness    = as.integer(d$succinctness),
    relevance       = as.integer(d$relevance),
    details         = as.character(d$details %||% "")
  )
}

format_qc_source = function(stats, params) {
  lines = c(
    paste0("Industries: ", paste(params$industry_labels, collapse = ", ")),
    paste0("Date range: ", params$start_month, " to ", params$end_month)
  )
  if (!is.null(stats) && !is.null(stats$per_industry) && nrow(stats$per_industry) > 0) {
    tbl = tryCatch(
      capture.output(print(as.data.frame(
        stats$per_industry %>% mutate(across(where(is.numeric), ~ round(.x, 2)))
      ), row.names = FALSE)),
      error = function(e) character(0)
    )
    if (length(tbl) > 0) lines = c(lines, "Summary statistics:", tbl)
  }
  paste(lines, collapse = "\n")
}

month_opts = month_choices("2018-01", "2025-12")

build_markdown_fragment = function(text) {
  text = paste(as.character(text %||% ""), collapse = "\n")
  if (!nzchar(trimws(text))) {
    return('<div class="empty-report">No report content available yet.</div>')
  }

  html = tryCatch(
    commonmark::markdown_html(
      text,
      hardbreaks = TRUE,
      smart = TRUE,
      extensions = TRUE
    ),
    error = function(e) NULL
  )

  if (is.null(html) && requireNamespace("markdown", quietly = TRUE)) {
    html = tryCatch(
      markdown::markdownToHTML(text = text, fragment.only = TRUE),
      error = function(e) NULL
    )
  }

  if (is.null(html)) {
    safe_text = htmltools::htmlEscape(text)
    return(paste0("<p>", gsub("\n", "<br/>", safe_text), "</p>"))
  }

  html
}

workflow_card_ui = function(title, role, status, input_text, output_text, status_class = "pending") {
  tags$div(
    class = "workflow-card",
    tags$div(
      class = "workflow-card-top",
      tags$div(
        tags$div(class = "workflow-eyebrow", title),
        tags$div(class = "workflow-role", role)
      ),
      tags$span(class = paste("status-badge", status_class), status)
    ),
    tags$div(class = "workflow-meta-label", "Input"),
    tags$p(class = "workflow-meta-value", input_text),
    tags$div(class = "workflow-meta-label", "Output"),
    tags$p(class = "workflow-meta-value", output_text)
  )
}

report_panel_ui = function(title, subtitle, output_id) {
  tags$div(
    class = "report-panel",
    tags$div(class = "report-title", title),
    tags$p(class = "report-subtitle", subtitle),
    uiOutput(output_id)
  )
}

metadata_item_ui = function(label, value) {
  tags$div(
    class = "metadata-item",
    tags$div(class = "metadata-label", label),
    tags$div(class = "metadata-value", value)
  )
}

has_report_content = function(x) {
  if (is.null(x)) return(FALSE)
  txt = paste(as.character(x), collapse = "\n")
  nzchar(trimws(txt))
}

app_css = "
:root {
  --page-bg: #f3f6fb;
  --page-bg-alt: #eef3f9;
  --card-bg: #ffffff;
  --card-border: #e5e7eb;
  --card-shadow: 0 12px 30px rgba(15, 23, 42, 0.06);
  --text-main: #0f172a;
  --text-muted: #64748b;
  --text-soft: #94a3b8;
  --primary: #0f766e;
  --primary-strong: #115e59;
  --secondary: #334155;
  --success-bg: #dcfce7;
  --success-text: #166534;
  --pending-bg: #f1f5f9;
  --pending-text: #475569;
}

html, body {
  background:
    radial-gradient(circle at top left, rgba(15, 118, 110, 0.08), transparent 30%),
    linear-gradient(180deg, var(--page-bg) 0%, var(--page-bg-alt) 100%);
  color: var(--text-main);
  font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 16px;
  line-height: 1.65;
}

/* Shiny withProgress / busy bar: pin bottom-right above cards and notifications */
.shiny-progress-container {
  position: fixed !important;
  bottom: 20px !important;
  right: 20px !important;
  top: auto !important;
  left: auto !important;
  z-index: 10060 !important;
  min-width: 220px;
  max-width: 360px;
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.12);
  border-radius: 12px;
  overflow: hidden;
}

body .container-fluid {
  max-width: 1600px;
  padding: 24px 20px 40px;
}

.page-header {
  background: linear-gradient(135deg, rgba(15, 118, 110, 0.12), rgba(255, 255, 255, 0.96));
  border: 1px solid rgba(15, 118, 110, 0.12);
  border-radius: 18px;
  box-shadow: var(--card-shadow);
  padding: 28px 30px;
  margin-bottom: 22px;
}

.header-kicker {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 12px;
  font-weight: 700;
  color: var(--primary);
  margin-bottom: 10px;
}

.page-header h1 {
  margin: 0 0 10px 0;
  font-size: 32px;
  font-weight: 800;
  line-height: 1.15;
  color: var(--text-main);
}

.page-header p {
  margin: 0;
  font-size: 15px;
  color: var(--text-muted);
  max-width: 980px;
}

.well,
.sidebar-panel,
.main-panel {
  background: transparent;
  border: none;
  box-shadow: none;
}

.control-panel {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 18px;
  box-shadow: var(--card-shadow);
  padding: 24px 22px;
}

.control-title {
  font-size: 20px;
  font-weight: 700;
  margin-bottom: 6px;
}

.control-subtitle {
  color: var(--text-muted);
  font-size: 14px;
  margin-bottom: 22px;
}

.control-panel .form-group,
.control-panel .shiny-input-container {
  margin-bottom: 18px;
}

.control-panel label,
.control-panel .control-label {
  font-size: 14px;
  font-weight: 700;
  color: var(--secondary);
  margin-bottom: 8px;
}

.control-panel .form-control,
.control-panel .selectize-input,
.control-panel .form-control:focus {
  min-height: 46px;
  border-radius: 12px;
  border-color: #d8dee8;
  box-shadow: none;
  font-size: 15px;
}

.control-panel .checkbox label,
.control-panel .radio label {
  font-weight: 500;
  color: var(--text-main);
}

.button-stack > * {
  width: 100%;
  margin-bottom: 12px;
}

.btn-run-query,
.btn-generate-report,
.control-panel .btn-warning,
.btn-download-report,
.btn-download-report-disabled {
  width: 100%;
  min-height: 46px;
  border-radius: 12px;
  font-weight: 700;
  font-size: 15px;
  border: none;
  box-shadow: none;
}

.btn-run-query {
  background: #e2e8f0;
  color: #0f172a;
}

.btn-run-query:hover {
  background: #cbd5e1;
  color: #0f172a;
}

.btn-generate-report {
  background: linear-gradient(135deg, var(--primary), #14b8a6);
  color: #ffffff;
}

.btn-generate-report:hover {
  background: linear-gradient(135deg, var(--primary-strong), var(--primary));
  color: #ffffff;
}

.control-panel .btn-warning,
.control-panel .btn-warning:hover,
.control-panel .btn-warning:focus {
  background: linear-gradient(135deg, #f59e0b, #fbbf24);
  color: #ffffff;
}

.btn-download-report {
  background: #0f172a;
  color: #ffffff;
}

.btn-download-report:hover {
  background: #1e293b;
  color: #ffffff;
}

.btn-download-report-disabled,
.btn-download-report-disabled:hover {
  background: #cbd5e1;
  color: #ffffff;
  cursor: not-allowed;
  opacity: 0.9;
}

.confirm-status,
.sidebar-status {
  margin-top: 14px;
}

.status-item {
  padding: 12px 14px;
  border-radius: 12px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  color: var(--text-main);
  margin-bottom: 10px;
}

.status-item strong {
  display: block;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-soft);
  margin-bottom: 4px;
}

.dashboard-shell {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.status-banner,
.workflow-overview,
.tab-shell {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 18px;
  box-shadow: var(--card-shadow);
}

.status-banner {
  padding: 16px 20px;
}

.status-banner.success {
  border-left: 4px solid #16a34a;
}

.status-banner.info {
  border-left: 4px solid #0ea5e9;
}

.status-banner.error {
  border-left: 4px solid #ef4444;
}

.status-banner strong {
  display: block;
  margin-bottom: 4px;
  font-size: 14px;
}

.status-banner span {
  color: var(--text-muted);
  font-size: 14px;
}

.workflow-overview {
  padding: 18px 20px 22px;
}

.section-heading {
  font-size: 20px;
  font-weight: 800;
  margin: 0;
}

.section-subheading {
  margin: 6px 0 18px;
  color: var(--text-muted);
  font-size: 14px;
}

.workflow-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 16px;
}

.workflow-card {
  background: #fbfdff;
  border: 1px solid #e5e7eb;
  border-radius: 16px;
  padding: 18px;
}

.workflow-card-top {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: flex-start;
  margin-bottom: 14px;
}

.workflow-eyebrow {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-soft);
  margin-bottom: 4px;
}

.workflow-role {
  font-size: 18px;
  font-weight: 700;
  line-height: 1.2;
}

.workflow-meta-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-soft);
  margin-bottom: 4px;
}

.workflow-meta-value {
  font-size: 14px;
  color: var(--text-main);
  margin-bottom: 12px;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 82px;
  padding: 6px 10px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 700;
}

.status-badge.complete {
  background: var(--success-bg);
  color: var(--success-text);
}

.status-badge.pending {
  background: var(--pending-bg);
  color: var(--pending-text);
}

.status-badge.fail {
  background: #fee2e2;
  color: #991b1b;
}

.qc-bool-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
  margin-bottom: 20px;
}

.qc-bool-item {
  background: #fbfdff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.qc-score-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
  margin-bottom: 20px;
}

.qc-score-item {
  background: #fbfdff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  padding: 16px 16px 14px;
}

.qc-score-number {
  font-size: 32px;
  font-weight: 800;
  color: var(--primary);
  line-height: 1;
}

.qc-score-denom {
  font-size: 14px;
  color: var(--text-muted);
  font-weight: 500;
}

.qc-overall-banner {
  background: linear-gradient(135deg, rgba(15, 118, 110, 0.08), rgba(255, 255, 255, 0.9));
  border: 1px solid rgba(15, 118, 110, 0.18);
  border-radius: 14px;
  padding: 18px 20px;
  margin-bottom: 20px;
  display: flex;
  align-items: center;
  gap: 18px;
}

.qc-overall-number {
  font-size: 48px;
  font-weight: 800;
  color: var(--primary);
  line-height: 1;
}

.qc-overall-label {
  font-size: 14px;
  color: var(--text-muted);
}

.qc-details-box {
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 14px 16px;
  font-size: 14px;
  color: var(--text-main);
  line-height: 1.6;
}

.btn-qc {
  background: linear-gradient(135deg, #7c3aed, #a78bfa);
  color: #ffffff;
}

.btn-qc:hover {
  background: linear-gradient(135deg, #6d28d9, #7c3aed);
  color: #ffffff;
}

.tab-shell {
  padding: 18px 20px 20px;
}

.tab-shell .nav-tabs {
  border-bottom: 1px solid #e2e8f0;
  margin-bottom: 18px;
}

.tab-shell .nav-tabs > li > a {
  border: none;
  border-radius: 12px 12px 0 0;
  color: var(--text-muted);
  font-weight: 700;
  padding: 12px 16px;
  background: transparent;
}

.tab-shell .nav-tabs > li.active > a,
.tab-shell .nav-tabs > li.active > a:focus,
.tab-shell .nav-tabs > li.active > a:hover {
  border: none;
  color: var(--primary);
  background: rgba(15, 118, 110, 0.08);
}

.report-panel {
  padding: 4px 4px 10px;
}

/* Avoid zero-height outputs when switching to Raw Data / Trends tabs */
.report-panel .shiny-datatable-output,
.report-panel .datatables,
.report-panel .shiny-plot-output {
  min-height: 220px;
}

.report-title {
  font-size: 22px;
  font-weight: 800;
  margin-bottom: 4px;
}

.report-subtitle {
  font-size: 14px;
  color: var(--text-muted);
  margin-bottom: 20px;
}

.report-markdown {
  font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 15px;
  line-height: 1.7;
  color: var(--text-main);
}

.report-markdown h1,
.report-markdown h2,
.report-markdown h3,
.report-markdown h4 {
  color: var(--text-main);
  font-weight: 800;
  line-height: 1.25;
  margin-top: 1.25rem;
  margin-bottom: 0.85rem;
}

.report-markdown h1 { font-size: 30px; }
.report-markdown h2 { font-size: 24px; }
.report-markdown h3 { font-size: 20px; }

.report-markdown p,
.report-markdown ul,
.report-markdown ol {
  margin-bottom: 1rem;
}

.report-markdown ul,
.report-markdown ol {
  padding-left: 1.25rem;
}

.report-markdown table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  margin: 1rem 0 1.25rem;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  overflow: hidden;
  font-size: 14px;
}

.report-markdown thead th {
  background: #f8fafc;
  color: var(--secondary);
  font-weight: 700;
}

.report-markdown th,
.report-markdown td {
  padding: 12px 14px;
  border-bottom: 1px solid #e2e8f0;
  text-align: left;
  vertical-align: top;
}

.report-markdown tr:last-child td {
  border-bottom: none;
}

.report-markdown code,
.report-markdown pre {
  font-family: inherit;
  background: #f8fafc;
  border-radius: 8px;
}

.metadata-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px;
}

.metadata-item {
  background: #fbfdff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  padding: 16px 16px 14px;
}

.metadata-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-soft);
  margin-bottom: 6px;
}

.metadata-value {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-main);
  word-break: break-word;
}

.empty-report,
.empty-state-card {
  background: #f8fafc;
  border: 1px dashed #cbd5e1;
  border-radius: 14px;
  padding: 18px;
  color: var(--text-muted);
}

.dataTables_wrapper .dataTables_paginate .paginate_button.current,
.dataTables_wrapper .dataTables_paginate .paginate_button.current:hover {
  background: rgba(15, 118, 110, 0.12) !important;
  border: 1px solid rgba(15, 118, 110, 0.18) !important;
  color: var(--primary) !important;
}

.alert {
  border-radius: 14px;
  border: 1px solid #e2e8f0;
  box-shadow: none;
}

@media (max-width: 1400px) {
  .workflow-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 900px) {
  .workflow-grid {
    grid-template-columns: 1fr;
  }
}
"

ui = fluidPage(
  theme = bs_theme(bootswatch = "flatly"),
  tags$head(
    tags$style(htmltools::HTML(app_css)),
    # DT/plot inside hidden tabs can initialize at zero width; refresh layout when a tab is shown.
    tags$script(HTML("
$(document).on('shown.bs.tab', 'a[data-toggle=\"tab\"], a[data-bs-toggle=\"tab\"], button[data-bs-toggle=\"tab\"]', function() {
  setTimeout(function() { $(window).trigger('resize'); }, 50);
});
"))
  ),
  tags$div(
    class = "page-header",
    tags$div(class = "header-kicker", "Multi-Agent Retail Reporting Dashboard"),
    tags$h1("AI-Powered MRTS Reporter"),
    tags$p("Query MRTS data, inspect the raw retail signal, and generate a chained multi-agent report where Agent 1 analyzes the data, Agent 2 writes from Agent 1 only, and Agent 3 formats from Agent 2 only.")
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      tags$div(
        class = "control-panel",
        tags$div(class = "control-title", "Query Controls"),
        tags$p(class = "control-subtitle", "Configure the retail query, run the data pull, and generate a polished multi-agent business report."),
        radioButtons(
          "industry_mode",
          "Industry selection mode",
          choices = c("Single-select" = "single", "Multi-select" = "multi"),
          selected = "multi"
        ),
        tags$p(
          class = "control-subtitle",
          style = "margin-top:-6px; margin-bottom:10px;",
          "Multi-select: open the box, search, then add up to two industries to compare. ",
          "Single- and multi-select use separate controls so both modes stay reliable."
        ),
        conditionalPanel(
          condition = "input.industry_mode == 'single'",
          selectizeInput(
            "industries_single",
            "Industry (select 1)",
            choices = MRTS_INDUSTRIES,
            selected = unname(MRTS_INDUSTRIES)[1],
            multiple = FALSE,
            options = list(
              plugins = list("remove_button"),
              placeholder = "Search and select one industry"
            )
          )
        ),
        conditionalPanel(
          condition = "input.industry_mode != 'single'",
          selectizeInput(
            "industries_multi",
            "Apply industries (select up to 2)",
            choices = MRTS_INDUSTRIES,
            selected = unname(MRTS_INDUSTRIES)[1:2],
            multiple = TRUE,
            options = list(
              maxItems = 2,
              plugins = list("remove_button"),
              placeholder = "Search — add up to 2 industries",
              hideSelected = FALSE
            )
          )
        ),
        actionButton("confirm_industries", "Confirm Selected Industry(ies)", class = "btn-warning"),
        tags$div(class = "confirm-status", uiOutput("industry_confirm_status")),
        selectInput("start_month", "Start month (YYYY-MM)", choices = month_opts, selected = "2020-01"),
        selectInput("end_month", "End month (YYYY-MM)", choices = month_opts, selected = tail(month_opts, 1)),
        selectInput("data_type", "Data type", choices = MRTS_DATA_TYPES, selected = "default"),
        checkboxInput("show_growth", "Show derived series (YoY% / MoM%)", value = FALSE),
        radioButtons(
          "growth_type",
          "Derived series type",
          choices = c("YoY %" = "yoy", "MoM %" = "mom"),
          selected = "yoy"
        ),
        tags$div(
          class = "button-stack",
          actionButton("run_query", "Run Query", class = "btn-run-query"),
          actionButton("generate_ai_report", "Generate Multi-Agent Report", class = "btn-generate-report"),
          uiOutput("download_button_ui")
        ),
        tags$hr(),
        tags$div(class = "control-title", style = "font-size:15px; margin-bottom:4px;", "Quality Control"),
        tags$p(class = "control-subtitle", "Evaluate Agent 3 output on accuracy, formality, clarity, and more."),
        selectInput(
          "qc_provider",
          "QC Provider",
          choices = c("Ollama (local)" = "ollama", "OpenAI (cloud)" = "openai"),
          selected = if (nzchar(Sys.getenv("OPENAI_API_KEY"))) "openai" else "ollama"
        ),
        tags$div(
          class = "button-stack",
          actionButton("run_qc", "Run Quality Control", class = "btn-qc")
        ),
        tags$hr(),
        tags$div(class = "sidebar-status", uiOutput("sidebar_status"))
      )
    ),
    mainPanel(
      width = 9,
      tags$div(
        class = "dashboard-shell",
        uiOutput("ai_status"),
        tags$div(
          class = "workflow-overview",
          tags$h2(class = "section-heading", "Workflow Overview"),
          tags$p(class = "section-subheading", "Agent 2 reads only Agent 1 output; Agent 3 reads only Agent 2 output; QC Validator evaluates Agent 3 output against the source data."),
          uiOutput("workflow_overview_ui")
        ),
        tags$div(
          class = "tab-shell",
          tabsetPanel(
            id = "dashboard_tabs",
            tabPanel(
              "Metadata",
              report_panel_ui(
                "Report Metadata",
                "A concise summary of query scope, model configuration, and workflow details for the current report.",
                "ai_metadata"
              )
            ),
            tabPanel(
              "Raw Data Preview",
              tags$div(
                class = "report-panel",
                tags$div(class = "report-title", "Raw Data Preview"),
                tags$p(class = "report-subtitle", "A concise view of the MRTS query results that feed Agent 1 analysis. The underlying query flow and filters remain unchanged."),
                uiOutput("data_message"),
                DTOutput("data_table")
              )
            ),
            tabPanel(
              "Trend Visualization",
              tags$div(
                class = "report-panel",
                tags$div(class = "report-title", "Trend Visualization"),
                tags$p(class = "report-subtitle", "Interactive trend view for the queried industries. Derived series controls remain fully functional."),
                uiOutput("trends_message"),
                plotOutput("trends_plot", height = "450px")
              )
            ),
            tabPanel(
              "Agent 1 Output",
              report_panel_ui(
                "Agent 1 Output",
                "Analyzes raw MRTS data and returns a structured factual summary.",
                "agent1_report_ui"
              )
            ),
            tabPanel(
              "Agent 2 Output",
              report_panel_ui(
                "Agent 2 Output",
                "Reads only Agent 1 output and converts it into a business-style draft.",
                "agent2_report_ui"
              )
            ),
            tabPanel(
              "Agent 3 Final Report",
              report_panel_ui(
                "Agent 3 Final Report",
                "Reads only Agent 2 output and improves clarity, formatting, and professionalism.",
                "agent3_report_ui"
              )
            ),
            tabPanel(
              "Quality Control",
              tags$div(
                class = "report-panel",
                tags$div(class = "report-title", "Quality Control Results"),
                tags$p(class = "report-subtitle", "Agent 3 final report evaluated against source data for accuracy, formality, faithfulness, clarity, succinctness, and relevance."),
                uiOutput("qc_status_ui"),
                uiOutput("qc_results_ui")
              )
            )
          )
        )
      )
    )
  )
)

server = function(input, output, session) {
  data_state = reactiveVal(NULL)
  data_error = reactiveVal(NULL)
  ai_state = reactiveVal(NULL)
  ai_error = reactiveVal(NULL)
  ai_generated_at = reactiveVal(NULL)
  confirmed_industries = reactiveVal(character(0))
  qc_state = reactiveVal(NULL)
  qc_error = reactiveVal(NULL)

  output$download_button_ui = renderUI({
    ai = ai_state()
    if (is.null(ai) || !is.list(ai) || !has_report_content(ai$agent3)) {
      return(tags$button("Download Report", class = "btn-download-report-disabled", disabled = "disabled"))
    }
    downloadButton("download_report", "Download Report", class = "btn-download-report")
  })

  # Single vs multi use separate selectize inputs (industries_single / industries_multi).
  # updateSelectizeInput() cannot flip Shiny's multiple= flag, so reusing one inputId broke
  # multi-select after toggling modes.

  normalize_industry_selection = function(x) {
    if (is.null(x)) return(character(0))
    x = as.character(x)
    x[nzchar(x)]
  }

  selected_industries = reactive({
    mode = input$industry_mode %||% "multi"
    if (identical(mode, "single")) {
      raw = normalize_industry_selection(input$industries_single)
      if (length(raw) == 0) return(character(0))
      return(raw[1])
    }
    raw = normalize_industry_selection(input$industries_multi)
    if (length(raw) <= 2) return(raw)
    raw[seq_len(2)]
  })

  labels_from_codes = function(codes) {
    labels = names(MRTS_INDUSTRIES)[match(codes, unname(MRTS_INDUSTRIES))]
    ifelse(is.na(labels), codes, labels)
  }

  selected_industry_labels = reactive({
    labels_from_codes(selected_industries())
  })

  confirmed_industry_labels = reactive({
    labels_from_codes(confirmed_industries())
  })

  output$industry_confirm_status = renderUI({
    confirmed = confirmed_industries()
    if (length(confirmed) == 0) {
      return(tags$div(class = "status-item", tags$strong("Industry confirm"), "No confirmed industries yet."))
    }
    tags$div(
      class = "status-item",
      tags$strong("Industry confirm"),
      glue("Confirmed: {paste(confirmed_industry_labels(), collapse = ', ')}")
    )
  })

  observeEvent(input$confirm_industries, {
    raw_selected = selected_industries()

    if (identical(input$industry_mode, "multi") && length(raw_selected) != 2) {
      showNotification("Please select exactly 2 industries in Multi-select mode, then click confirm.", type = "error")
      return()
    }
    if (identical(input$industry_mode, "single") && length(raw_selected) != 1) {
      showNotification("Please select 1 industry in Single-select mode, then click confirm.", type = "error")
      return()
    }
    if (input$start_month > input$end_month) {
      showNotification("Start month must be <= end month before confirming.", type = "error")
      return()
    }

    if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
      showNotification("API check failed: CENSUS_API_KEY is not set.", type = "error", duration = 8)
      return()
    }

    # Do not use return() inside withProgress({}): in Shiny observers it returns
    # from the whole observeEvent callback, so probe is never assigned and no
    # error notification runs (button appears to do nothing).
    # Last expression in withProgress({}) must be the probe result — not incProgress() (that returns NULL).
    probe = withProgress(message = "Confirming industries…", value = 0, {
      incProgress(0.15, detail = "Validating and probing MRTS API")
      incProgress(0.45, detail = "Calling Census API")
      probe_query = list(
        get = "data_type_code,time_slot_id,seasonally_adj,category_code,cell_value",
        `for` = "us:*",
        time = "2023",
        seasonally_adj = "no",
        key = Sys.getenv("CENSUS_API_KEY")
      )
      resp = try(httr::GET(MRTS_ENDPOINTS[1], query = probe_query, httr::timeout(10)), silent = TRUE)
      probe_out = if (inherits(resp, "try-error")) {
        list(ok = FALSE, msg = as.character(resp))
      } else if (httr::status_code(resp) != 200) {
        txt = httr::content(resp, "text", encoding = "UTF-8")
        list(ok = FALSE, msg = sanitize_api_error(txt))
      } else {
        parsed = try(jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE), silent = TRUE)
        if (inherits(parsed, "try-error") || !is.list(parsed) || length(parsed) < 2) {
          list(ok = FALSE, msg = "Probe returned invalid response body.")
        } else {
          list(ok = TRUE, msg = "OK")
        }
      }
      incProgress(0.95, detail = "Finishing")
      probe_out
    })

    if (!isTRUE(probe$ok)) {
      showNotification(glue("API check failed: {probe$msg}"), type = "error", duration = 8)
      return()
    }

    confirmed_industries(raw_selected)
    showNotification(glue("Confirmed {length(raw_selected)} industry(ies). API probe passed."), type = "message", duration = 6)
  }, ignoreInit = TRUE)

  observeEvent(input$run_query, {
    ai_state(NULL)
    ai_error(NULL)
    ai_generated_at(NULL)
    data_error(NULL)

    industries = selected_industries()
    if (length(industries) == 0) {
      msg = "No industry selected. Please check 1 or 2 industries first."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "error")
      return()
    }
    if (identical(input$industry_mode, "multi") && length(industries) != 2) {
      msg = "In Multi-select mode, please check exactly 2 industries."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    if (input$start_month > input$end_month) {
      msg = "Start month is after end month. Please fix the date range."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    query_params = list(
      industries = industries,
      start_month = input$start_month,
      end_month = input$end_month,
      data_type = input$data_type
    )

    out = withProgress(message = "Running MRTS query…", value = 0, {
      incProgress(0.08, detail = "Starting request")
      incProgress(0.25, detail = "Fetching Census MRTS (may take a moment)")
      result = tryCatch(
        fetch_mrts_data(query_params),
        error = function(e) e
      )
      incProgress(1, detail = "Done")
      result
    })

    if (inherits(out, "error")) {
      msg = conditionMessage(out)
      data_state(NULL)
      data_error(msg)
      showNotification(glue("API query failed: {msg}"), type = "error")
      return()
    }

    if (nrow(out) == 0) {
      msg = "API returned empty data for your selection."
      data_state(out)
      data_error(msg)
      showNotification(msg, type = "warning")
      return()
    }

    # Check for date range warning and notify user
    date_warning = attr(out, "date_range_warning")
    if (!is.null(date_warning)) {
      showNotification(date_warning, type = "warning", duration = 10)
    }

    data_state(out)
    data_error(NULL)
    showNotification(glue("Query complete: {nrow(out)} rows loaded."), type = "message")
  }, ignoreInit = TRUE)

  output$sidebar_status = renderUI({
    data = data_state()
    key_set = nzchar(Sys.getenv("CENSUS_API_KEY"))
    current_labels = selected_industry_labels()
    tags$div(
      tags$div(
        class = "status-item",
        tags$strong("API"),
        if (key_set) "CENSUS_API_KEY configured" else "CENSUS_API_KEY not set"
      ),
      tags$div(
        class = "status-item",
        tags$strong("Selection"),
        if (length(current_labels) == 0) "No industries selected"
        else glue("{paste(current_labels, collapse = ', ')}")
      ),
      tags$div(
        class = "status-item",
        tags$strong("Confirmed scope"),
        if (length(confirmed_industries()) == 0) "Pending industry confirmation"
        else glue("{paste(confirmed_industry_labels(), collapse = ', ')}")
      ),
      tags$div(
        class = "status-item",
        tags$strong("Rows loaded"),
        if (is.null(data)) "No query run yet" else glue("{nrow(data)} rows ready")
      )
    )
  })

  output$data_message = renderUI({
    err = data_error()
    data = data_state()
    if (!is.null(err)) {
      return(div(class = "alert alert-warning", strong("Notice: "), err))
    }
    if (is.null(data)) {
      return(div(class = "alert alert-info", "Click 'Run Query' to fetch MRTS data."))
    }
    div(class = "alert alert-success", glue("Rows returned: {nrow(data)}"))
  })

  output$data_table = renderDT({
    data = data_state()
    
    # Check if data exists
    if (is.null(data)) {
      return(datatable(
        data.frame(Message = "Run Query to load data.", stringsAsFactors = FALSE),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      ))
    }
    
    if (nrow(data) == 0) {
      return(datatable(
        data.frame(Message = "No data to display for this selection.", stringsAsFactors = FALSE),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      ))
    }

    # Convert to data.frame and handle different column types
    tryCatch({
      safe_df = as.data.frame(data, stringsAsFactors = FALSE)
      
      # Convert Date columns to character
      for (col_name in names(safe_df)) {
        if (inherits(safe_df[[col_name]], "Date")) {
          safe_df[[col_name]] = format(safe_df[[col_name]], "%Y-%m-%d")
        } else if (is.list(safe_df[[col_name]])) {
          safe_df[[col_name]] = vapply(safe_df[[col_name]], function(x) {
            paste(as.character(unlist(x)), collapse = ", ")
          }, character(1))
        } else if (!is.numeric(safe_df[[col_name]]) && !is.character(safe_df[[col_name]])) {
          safe_df[[col_name]] = as.character(safe_df[[col_name]])
        }
      }
      
      # Ensure all columns are valid for DT
      safe_df = safe_df[, sapply(safe_df, function(x) !all(is.na(x))), drop = FALSE]
      
      if (ncol(safe_df) == 0) {
        return(datatable(
          data.frame(Message = "No valid columns to display.", stringsAsFactors = FALSE),
          options = list(dom = "t", pageLength = 1),
          rownames = FALSE
        ))
      }

      safe_df[] = lapply(safe_df, as.character)
      names(safe_df) = make.names(names(safe_df), unique = TRUE)

      datatable(
        safe_df,
        options = list(
          pageLength = 15,
          scrollX = TRUE,
          dom = "ftip"
        ),
        rownames = FALSE
      )
    }, error = function(e) {
      datatable(
        data.frame(
          Error = paste("Table render error:", conditionMessage(e)),
          stringsAsFactors = FALSE
        ),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      )
    })
  })

  trend_df = reactive({
    df = data_state()
    
    if (is.null(df)) {
      return(data.frame())
    }
    
    if (nrow(df) == 0) {
      return(data.frame())
    }
    
    # Ensure required columns exist
    required_cols = c("month", "value", "industry")
    missing_cols = setdiff(required_cols, names(df))
    if (length(missing_cols) > 0) {
      return(data.frame())
    }

    tryCatch({
      # Determine primary data_type: use selected one, or "SM" if "default"
      primary_dtype = if (input$data_type == "default") "SM" else input$data_type
      
      ms_col = "month_str" %in% names(df)
      # month from API pipeline is usually already Date; ym() cannot parse "2024-05-01"-style strings → all NA → empty chart
      normalize_trend_month = function(m_raw, month_str_vec) {
        if (inherits(m_raw, "Date")) {
          return(as.Date(m_raw))
        }
        if (inherits(m_raw, "POSIXct")) {
          return(as.Date(m_raw))
        }
        parse_mrts_month(dplyr::coalesce(
          as.character(m_raw),
          if (!is.null(month_str_vec)) as.character(month_str_vec) else NA_character_
        ))
      }
      df_filtered = df %>%
        mutate(
          month = normalize_trend_month(.data$month, if (ms_col) .data$month_str else NULL),
          value = suppressWarnings(as.numeric(value)),
          industry = as.character(industry)
        ) %>%
        filter(!is.na(month), !is.na(value), !is.na(industry), nzchar(industry))
      
      target = toupper(trimws(as.character(primary_dtype)))
      # If data_type column exists, filter to primary sequence (Census SM/IM; tolerate case/whitespace)
      if ("data_type" %in% names(df_filtered)) {
        df_filtered = df_filtered %>%
          mutate(.dtype_norm = toupper(trimws(as.character(data_type)))) %>%
          filter(.dtype_norm == target) %>%
          select(-.dtype_norm)
        if (nrow(df_filtered) == 0) {
          df_all = df %>%
            mutate(
              month = normalize_trend_month(.data$month, if (ms_col) .data$month_str else NULL),
              value = suppressWarnings(as.numeric(value)),
              industry = as.character(industry)
            ) %>%
            filter(!is.na(month), !is.na(value), !is.na(industry), nzchar(industry))
          if ("data_type" %in% names(df_all)) {
            cand = unique(toupper(trimws(as.character(df_all$data_type))))
            cand = cand[!is.na(cand) & nzchar(cand)]
            if (length(cand) > 0) {
              pick = if (target %in% cand) target else cand[[1]]
              df_filtered = df_all %>% filter(toupper(trimws(as.character(data_type))) == pick)
            }
          }
        }
      }
      
      # Aggregate to one point per industry-month, then calculate derived metrics
      df_filtered %>%
        group_by(industry, month) %>%
        summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
        arrange(industry, month) %>%
        group_by(industry) %>%
        mutate(
          # Safe YoY calculation: avoid division by zero and clamp extreme values
          yoy = if_else(
            is.na(lag(value, 12)) | abs(lag(value, 12)) < 1e-6,
            NA_real_,
            pmax(-1000, pmin(10000, 100 * (value / lag(value, 12) - 1)))
          ),
          # Safe MoM calculation: avoid division by zero and clamp extreme values
          mom = if_else(
            is.na(lag(value, 1)) | abs(lag(value, 1)) < 1e-6,
            NA_real_,
            pmax(-1000, pmin(10000, 100 * (value / lag(value, 1) - 1)))
          )
        ) %>%
        ungroup()
    }, error = function(e) {
      data.frame()
    })
  })

  output$trends_plot = renderPlot({
    df = trend_df()
    
    # Check if data exists
    if (is.null(df) || nrow(df) == 0) {
      plot.new()
      text(0.5, 0.5, "No trend data available. Run Query first.", cex = 1.2)
      return(invisible(NULL))
    }

    # Determine which column to plot
    y_col = if (isTRUE(input$show_growth) && input$growth_type == "yoy") "yoy" else if (isTRUE(input$show_growth)) "mom" else "value"
    y_label = if (y_col == "yoy") "YoY % change" else if (y_col == "mom") "MoM % change" else "Sales value"
    
    # Ensure the column exists
    if (!y_col %in% names(df)) {
      y_col = "value"
      y_label = "Sales value"
    }

    # Filter and prepare data for plotting
    df_plot = df %>%
      filter(!is.na(month), !is.na(.data[[y_col]]), !is.na(industry), nzchar(industry)) %>%
      arrange(industry, month)

    if (nrow(df_plot) == 0) {
      plot.new()
      text(0.5, 0.5, "No valid data points after filtering.", cex = 1.2)
      return(invisible(NULL))
    }

    tryCatch({
      # Use base plotting here to avoid device/text rendering regressions in some deployments
      wide_df = df_plot %>%
        select(month, industry, y = all_of(y_col)) %>%
        tidyr::pivot_wider(names_from = industry, values_from = y, values_fn = mean) %>%
        arrange(month)

      x = as.Date(wide_df$month)
      y_mat = as.matrix(wide_df[, setdiff(names(wide_df), "month"), drop = FALSE])
      storage.mode(y_mat) = "double"

      if (length(x) == 0 || ncol(y_mat) == 0) {
        plot.new()
        text(0.5, 0.5, "No valid series to plot.")
        return(invisible(NULL))
      }

      yr = range(y_mat, na.rm = TRUE)
      if (!all(is.finite(yr))) {
        plot.new()
        text(0.5, 0.5, "No finite values to plot.")
        return(invisible(NULL))
      }

      cols = grDevices::hcl.colors(max(3, ncol(y_mat)), "Dark 3")[seq_len(ncol(y_mat))]
      plot(
        x, y_mat[, 1],
        type = "l", lwd = 2, col = cols[1],
        xlab = "Month", ylab = y_label, ylim = yr,
        main = "Monthly Retail Trend by Industry"
      )
      if (ncol(y_mat) > 1) {
        for (i in 2:ncol(y_mat)) {
          lines(x, y_mat[, i], col = cols[i], lwd = 2)
        }
      }
      legend("topright", legend = colnames(y_mat), col = cols, lty = 1, lwd = 2, bty = "n", cex = 0.85)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Plot error:", conditionMessage(e)), cex = 1.2)
    })
  })
  
  output$trends_message = renderUI({
    raw = data_state()
    tf = trend_df()
    if (is.null(raw) || nrow(raw) == 0) {
      return(div(class = "alert alert-info", "Run Query first to see trends chart."))
    }
    if (nrow(tf) == 0) {
      return(div(
        class = "alert alert-warning",
        tags$strong("Trend data could not be built from the current table. "),
        glue("Raw query has {nrow(raw)} rows — check `month` / `data_type` in Raw Data Preview, or wait for the query to finish.")
      ))
    }
    div(
      class = "alert alert-success",
      glue(
        "Chart: {nrow(tf)} industry-month rows, {length(unique(tf$industry))} series (raw query {nrow(raw)} rows)."
      )
    )
  })

  observeEvent(input$generate_ai_report, {
    ai_error(NULL)
    df = data_state()

    if (is.null(df) || nrow(df) == 0) {
      msg = "No query data available. Click Run Query first."
      ai_state(NULL)
      ai_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    # Filter to primary data_type only for AI report (same logic as trend_df)
    primary_dtype = if (input$data_type == "default") "SM" else input$data_type
    df_primary = df
    
    # If data_type column exists, filter to primary sequence only
    if ("data_type" %in% names(df_primary)) {
      df_primary = df_primary %>%
        filter(data_type == primary_dtype)
      
      if (nrow(df_primary) == 0) {
        msg = glue("No data available for data_type '{primary_dtype}'. Try a different data type.")
        ai_state(NULL)
        ai_error(msg)
        showNotification(msg, type = "error")
        return()
      }
    }
    
    # Compute stats only on primary sequence
    stats = compute_summary_stats(df_primary)
    params = list(
      industry_labels = selected_industry_labels(),
      start_month = input$start_month,
      end_month = input$end_month,
      data_type = input$data_type,
      primary_data_type = primary_dtype,  # Add this for AI prompt clarity
      endpoint = MRTS_ENDPOINTS[1]
    )

    report = withProgress(message = "Generating multi-agent report…", value = 0, {
      incProgress(0.05, detail = "Preparing prompts and statistics")
      incProgress(0.12, detail = "Running Agent 1 → 2 → 3 (often 1–5+ minutes)")
      r = tryCatch(
        generate_multi_agent_report(df_primary, stats, params),
        error = function(e) e
      )
      incProgress(1, detail = "Complete")
      r
    })

    if (inherits(report, "error")) {
      msg = conditionMessage(report)
      ai_state(NULL)
      ai_error(msg)
      showNotification(glue("AI generation failed: {msg}"), type = "error")
      return()
    }

    # Safely extract attributes with defaults
    model_attr = attr(report, "model_used")
    backend_attr = attr(report, "backend")
    
    ai_state(list(
      text = as.character(report$final),
      agent1 = as.character(report$agent1),
      agent2 = as.character(report$agent2),
      agent3 = as.character(report$agent3),
      model = if (is.null(model_attr)) "unknown" else as.character(model_attr),
      backend = if (is.null(backend_attr)) "unknown" else as.character(backend_attr),
      stats = stats,
      params = params
    ))
    ai_generated_at(Sys.time())
    showNotification("Multi-agent report generated successfully.", type = "message")
  }, ignoreInit = TRUE)

  output$ai_status = renderUI({
    err = ai_error()
    ai = ai_state()
    if (!is.null(err)) {
      return(tags$div(class = "status-banner error", tags$strong("Multi-agent generation failed"), tags$span(err)))
    }
    if (is.null(ai)) {
      return(tags$div(class = "status-banner info", tags$strong("Multi-agent report not generated yet"), tags$span("Run a query, then generate the chained report to populate Agent 1, Agent 2, and Agent 3 outputs.")))
    }
    tags$div(class = "status-banner success", tags$strong("Multi-agent report ready"), tags$span("The dashboard now contains the complete chain: Raw Data -> Agent 1 -> Agent 2 -> Agent 3."))
  })

  output$workflow_overview_ui = renderUI({
    ai  = ai_state()
    qc  = qc_state()
    agent1_done = is.list(ai) && has_report_content(ai$agent1)
    agent2_done = is.list(ai) && has_report_content(ai$agent2)
    agent3_done = is.list(ai) && has_report_content(ai$agent3)
    qc_done     = is.list(qc) && !is.null(qc$accuracy)

    tags$div(
      class = "workflow-grid",
      workflow_card_ui(
        "Agent 1",
        "Data Analyst",
        if (agent1_done) "Complete" else "Waiting",
        "Raw MRTS data",
        "Structured factual summary",
        if (agent1_done) "complete" else "pending"
      ),
      workflow_card_ui(
        "Agent 2",
        "Report Writer",
        if (agent2_done) "Complete" else "Waiting",
        "Agent 1 output only",
        "Business-style draft report",
        if (agent2_done) "complete" else "pending"
      ),
      workflow_card_ui(
        "Agent 3",
        "Formatter / QA",
        if (agent3_done) "Complete" else "Waiting",
        "Agent 2 output only",
        "Final polished report",
        if (agent3_done) "complete" else "pending"
      ),
      workflow_card_ui(
        "QC Validator",
        "Quality Control",
        if (qc_done) "Complete" else "Waiting",
        "Agent 3 output + source data",
        "Accuracy, formality & Likert scores",
        if (qc_done) "complete" else "pending"
      )
    )
  })

  output$ai_metadata = renderUI({
    ai = ai_state()
    if (is.null(ai) || !is.list(ai)) {
      return(tags$div(class = "empty-state-card", "Generate a multi-agent report to view the query scope, selected model, and workflow metadata."))
    }

    industry_labels = if (is.list(ai$params) && !is.null(ai$params$industry_labels)) {
      paste(ai$params$industry_labels, collapse = ", ")
    } else { "N/A" }
    
    start_month = if (is.list(ai$params) && !is.null(ai$params$start_month)) {
      ai$params$start_month
    } else { "N/A" }
    
    end_month = if (is.list(ai$params) && !is.null(ai$params$end_month)) {
      ai$params$end_month
    } else { "N/A" }
    
    total_rows = if (is.list(ai$stats) && !is.null(ai$stats$total_rows)) {
      ai$stats$total_rows
    } else { 0 }
    
    backend = if (!is.null(ai$backend)) ai$backend else "unknown"
    model = if (!is.null(ai$model)) ai$model else "unknown"
    
    endpoint = if (is.list(ai$params) && !is.null(ai$params$endpoint)) {
      ai$params$endpoint
    } else { "N/A" }

    tags$div(
      class = "metadata-grid",
      metadata_item_ui("Industries selected", industry_labels),
      metadata_item_ui("Date range", paste(start_month, "to", end_month)),
      metadata_item_ui("Rows", total_rows),
      metadata_item_ui("Generated at", as.character(ai_generated_at())),
      metadata_item_ui("Model used", paste(backend, "-", model)),
      metadata_item_ui("Endpoint", endpoint),
      metadata_item_ui("Workflow", "Raw Data -> Agent 1 -> Agent 2 -> Agent 3")
    )
  })

  output$agent1_report_ui = renderUI({
    ai = ai_state()
    if (is.null(ai) || !is.list(ai) || !has_report_content(ai$agent1)) {
      return(tags$div(class = "empty-state-card", "No Agent 1 output yet. Generate the multi-agent report to populate this section."))
    }
    txt = paste(as.character(ai$agent1), collapse = "\n")
    tryCatch(
      tags$div(class = "report-markdown", htmltools::HTML(build_markdown_fragment(txt))),
      error = function(e) tags$div(class = "empty-state-card", paste("Agent 1 render error:", conditionMessage(e)))
    )
  })

  output$agent2_report_ui = renderUI({
    ai = ai_state()
    if (is.null(ai) || !is.list(ai) || !has_report_content(ai$agent2)) {
      return(tags$div(class = "empty-state-card", "No Agent 2 output yet. Generate the multi-agent report to populate this section."))
    }
    txt = paste(as.character(ai$agent2), collapse = "\n")
    tryCatch(
      tags$div(class = "report-markdown", htmltools::HTML(build_markdown_fragment(txt))),
      error = function(e) tags$div(class = "empty-state-card", paste("Agent 2 render error:", conditionMessage(e)))
    )
  })

  output$agent3_report_ui = renderUI({
    ai = ai_state()
    if (is.null(ai) || !is.list(ai) || !has_report_content(ai$agent3)) {
      return(tags$div(class = "empty-state-card", "No Agent 3 final report yet. Generate the multi-agent report to populate this section."))
    }
    txt = paste(as.character(ai$agent3), collapse = "\n")
    tryCatch(
      tags$div(class = "report-markdown", htmltools::HTML(build_markdown_fragment(txt))),
      error = function(e) tags$div(class = "empty-state-card", paste("Agent 3 render error:", conditionMessage(e)))
    )
  })

  # ── Quality Control ────────────────────────────────────────────────────────

  observeEvent(input$run_qc, {
    qc_state(NULL)
    qc_error(NULL)
    ai = ai_state()

    if (is.null(ai) || !is.list(ai) || !has_report_content(ai$agent3)) {
      msg = "No Agent 3 report available. Generate the multi-agent report first."
      qc_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    provider = input$qc_provider
    # Do not use `nchar(...) > 0 |> { function(x)... }()` — R parses it as `nchar(...) > (function(...)(0))`, yielding TRUE/FALSE, not the model string.
    oh = trimws(Sys.getenv("OLLAMA_HOST", ""))
    ollama_host = if (nzchar(oh) && !is_env_placeholder(oh)) oh else "http://localhost:11434"
    om = trimws(Sys.getenv("OLLAMA_MODEL", ""))
    ollama_model = if (nzchar(om) && !is_env_placeholder(om)) om else "smollm2:1.7b"
    openai_key = Sys.getenv("OPENAI_API_KEY")
    om_oai = trimws(Sys.getenv("OPENAI_MODEL", ""))
    openai_model = if (nzchar(om_oai) && !is_env_placeholder(om_oai)) om_oai else "gpt-4o-mini"

    source_data = format_qc_source(ai$stats, ai$params)
    prompt = create_qc_prompt(paste(as.character(ai$agent3), collapse = "\n"), source_data)

    result = withProgress(message = "Running quality control…", value = 0, {
      incProgress(0.08, detail = "Building QC prompt")
      incProgress(0.18, detail = glue("Calling {provider} (waiting for model)"))
      tryCatch(
        {
          raw = query_ai_qc(prompt, provider, ollama_host, ollama_model, openai_key, openai_model)
          incProgress(0.82, detail = "Parsing JSON results")
          out = parse_qc_results(raw)
          incProgress(1, detail = "Done")
          out
        },
        error = function(e) e
      )
    })

    if (inherits(result, "error")) {
      msg = strip_cli_ansi(conditionMessage(result))
      qc_error(msg)
      showNotification(glue("Quality control failed: {msg}"), type = "error")
      return()
    }

    qc_state(result)
    showNotification("Quality control complete.", type = "message")
  }, ignoreInit = TRUE)

  output$qc_status_ui = renderUI({
    err = qc_error()
    qc  = qc_state()
    if (!is.null(err)) {
      return(tags$div(class = "status-banner error", tags$strong("Quality control failed"), tags$span(err)))
    }
    if (is.null(qc)) {
      return(tags$div(class = "alert alert-info", "Generate the multi-agent report first, then click 'Run Quality Control'."))
    }
    NULL
  })

  output$qc_results_ui = renderUI({
    qc = qc_state()
    if (is.null(qc)) return(NULL)

    bool_badge = function(val, label) {
      if (is.na(val)) cls = "pending" else if (isTRUE(val)) cls = "complete" else cls = "fail"
      txt = if (is.na(val)) "N/A" else if (isTRUE(val)) "PASS" else "FAIL"
      tags$div(
        class = "qc-bool-item",
        tags$div(class = "metadata-label", label),
        tags$span(class = paste("status-badge", cls), txt)
      )
    }

    score_card = function(label, val) {
      tags$div(
        class = "qc-score-item",
        tags$div(class = "metadata-label", label),
        tags$div(
          tags$span(class = "qc-score-number", val),
          tags$span(class = "qc-score-denom", " / 5")
        )
      )
    }

    overall = mean(c(qc$accuracy, qc$formality, qc$faithfulness,
                     qc$clarity, qc$succinctness, qc$relevance), na.rm = TRUE)

    tagList(
      tags$div(
        class = "qc-overall-banner",
        tags$div(class = "qc-overall-number", round(overall, 1)),
        tags$div(
          tags$div(style = "font-size:18px; font-weight:700;", "Overall Quality Score"),
          tags$div(class = "qc-overall-label", "Average of 6 Likert scale criteria (out of 5.0)")
        )
      ),
      tags$div(class = "metadata-label", style = "margin-bottom:10px;", "Boolean Checks"),
      tags$div(
        class = "qc-bool-grid",
        bool_badge(qc$accurate,        "Factually Accurate"),
        bool_badge(qc$no_contractions, "No Contractions"),
        bool_badge(qc$no_hyperbole,    "No Hyperbole")
      ),
      tags$div(class = "metadata-label", style = "margin-bottom:10px;", "Likert Scale Scores"),
      tags$div(
        class = "qc-score-grid",
        score_card("Accuracy",    qc$accuracy),
        score_card("Formality",   qc$formality),
        score_card("Faithfulness",qc$faithfulness),
        score_card("Clarity",     qc$clarity),
        score_card("Succinctness",qc$succinctness),
        score_card("Relevance",   qc$relevance)
      ),
      tags$div(class = "metadata-label", style = "margin-bottom:8px;", "AI Assessment"),
      tags$div(class = "qc-details-box", qc$details)
    )
  })

  output$download_report = downloadHandler(
    filename = function() {
      paste0("mrts_ai_report_", format(Sys.Date(), "%Y%m%d"), ".md")
    },
    content = function(file) {
      ai = ai_state()
      if (is.null(ai)) {
        showNotification("Generate Multi-Agent Report before downloading.", type = "error")
        writeLines("No multi-agent report generated yet. Please click 'Generate Multi-Agent Report' first.", file)
        return()
      }

      withProgress(message = "Preparing download…", value = 0, {
        incProgress(0.15, detail = "Gathering report sections")

        # Safely access nested fields
        if (!is.list(ai) || !is.list(ai$stats) || is.null(ai$stats$per_industry)) {
          stats_tbl = data.frame()
        } else {
          stats_tbl = ai$stats$per_industry %>%
            mutate(across(where(is.numeric), ~ round(.x, 2)))
        }

        # Safely extract params with defaults
        industry_labels = if (is.list(ai$params) && !is.null(ai$params$industry_labels)) {
          paste(ai$params$industry_labels, collapse = ", ")
        } else { "N/A" }

        start_month = if (is.list(ai$params) && !is.null(ai$params$start_month)) {
          ai$params$start_month
        } else { "N/A" }

        end_month = if (is.list(ai$params) && !is.null(ai$params$end_month)) {
          ai$params$end_month
        } else { "N/A" }

        data_type = if (is.list(ai$params) && !is.null(ai$params$data_type)) {
          ai$params$data_type
        } else { "N/A" }

        endpoint = if (is.list(ai$params) && !is.null(ai$params$endpoint)) {
          ai$params$endpoint
        } else { "N/A" }

        backend = if (!is.null(ai$backend)) ai$backend else "unknown"
        model = if (!is.null(ai$model)) ai$model else "unknown"

        incProgress(0.45, detail = "Building markdown")

        header = c(
          "# AI-Powered MRTS Multi-Agent Report",
          "",
          glue("- Generated: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}"),
          glue("- Industries: {industry_labels}"),
          glue("- Date range: {start_month} to {end_month}"),
          glue("- Data type: {data_type}"),
          glue("- Endpoint: {endpoint}"),
          glue("- Model: {backend} / {model}"),
          "- Workflow: Raw Data -> Agent 1 -> Agent 2 -> Agent 3",
          ""
        )

        stats_lines = if (nrow(stats_tbl) > 0) {
          capture.output(print(stats_tbl, row.names = FALSE))
        } else {
          "No statistics available."
        }

        agent1_text = if (!is.null(ai$agent1) && is.character(ai$agent1)) ai$agent1 else if (!is.null(ai$agent1)) as.character(ai$agent1) else "No Agent 1 output available."
        agent2_text = if (!is.null(ai$agent2) && is.character(ai$agent2)) ai$agent2 else if (!is.null(ai$agent2)) as.character(ai$agent2) else "No Agent 2 output available."
        agent3_text = if (!is.null(ai$agent3) && is.character(ai$agent3)) ai$agent3 else if (!is.null(ai$agent3)) as.character(ai$agent3) else "No Agent 3 final report available."

        report_lines = c(
          header,
          "## Agent 1 Output",
          "",
          agent1_text,
          "",
          "## Agent 2 Output",
          "",
          agent2_text,
          "",
          "## Agent 3 Final Report",
          "",
          agent3_text,
          "",
          "## Data Summary (Per-Industry Stats)",
          "",
          "```",
          stats_lines,
          "```"
        )
        incProgress(0.9, detail = "Writing file")
        writeLines(report_lines, file)
        incProgress(1, detail = "Done")
      })
    }
  )

  # Must run after all output$ assignments: outputOptions targets must already exist.
  outputOptions(output, "ai_metadata", suspendWhenHidden = FALSE)
  outputOptions(output, "workflow_overview_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "agent1_report_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "agent2_report_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "agent3_report_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "download_button_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "qc_results_ui", suspendWhenHidden = FALSE)
  outputOptions(output, "qc_status_ui", suspendWhenHidden = FALSE)
  # Tables/plots in tabPanels: keep updating when hidden so DT/plot initialize with real width when opened
  outputOptions(output, "data_table", suspendWhenHidden = FALSE)
  outputOptions(output, "data_message", suspendWhenHidden = FALSE)
  outputOptions(output, "trends_plot", suspendWhenHidden = FALSE)
  outputOptions(output, "trends_message", suspendWhenHidden = FALSE)
}

shinyApp(ui = ui, server = server)
