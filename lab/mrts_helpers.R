# Helper functions for MRTS AI-powered reporter

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(lubridate)
  library(glue)
})

MRTS_ENDPOINTS = c(
  "https://api.census.gov/data/timeseries/eits/mrts"
)

MRTS_INDUSTRIES = c(
  "Retail & Food Services (44X72)" = "44X72",
  "Retail Trade (44X45)" = "44X45",
  "Food Services & Drinking Places (722)" = "722",
  "Motor Vehicle & Parts Dealers (441)" = "441",
  "Nonstore Retailers (454)" = "454",
  "General Merchandise Stores (452)" = "452",
  "Food & Beverage Stores (445)" = "445"
)

MRTS_DATA_TYPES = c(
  "Default" = "default",
  "Sales (SM)" = "SM",
  "Inventories (IM)" = "IM"
)

month_choices = function(from = "2018-01", to = format(Sys.Date(), "%Y-%m")) {
  start_date = as.Date(paste0(from, "-01"))
  end_date = as.Date(paste0(to, "-01"))
  format(seq.Date(start_date, end_date, by = "month"), "%Y-%m")
}

industry_code_match = function(category_code, selected_code) {
  category_code = as.character(category_code)
  selected_code = as.character(selected_code)
  if (!nzchar(selected_code)) return(rep(FALSE, length(category_code)))

  # MRTS aggregate groups often use X ranges (e.g., 44X45, 44X72).
  if (identical(selected_code, "44X45")) {
    return(grepl("^(44|45)", category_code) | category_code == "44X45")
  }
  if (identical(selected_code, "44X72")) {
    return(grepl("^(44|45|72)", category_code) | category_code == "44X72")
  }

  # Generic X wildcard fallback (X -> any digit sequence)
  if (grepl("X", selected_code)) {
    pattern = paste0("^", gsub("X", "[0-9]*", selected_code), "$")
    return(grepl(pattern, category_code))
  }

  # Exact or prefix match for regular NAICS-like codes (e.g., 445, 722)
  category_code == selected_code | startsWith(category_code, selected_code)
}

keep_selected_industries = function(df, selected_codes) {
  if (length(selected_codes) == 0) return(df[0, , drop = FALSE])
  keep_idx = rep(FALSE, nrow(df))
  for (code in selected_codes) {
    keep_idx = keep_idx | industry_code_match(df$industry_code, code)
  }
  df[keep_idx, , drop = FALSE]
}

expand_selected_industries = function(df, selected_codes) {
  if (length(selected_codes) == 0) return(df[0, , drop = FALSE])
  expanded = purrr::map_dfr(selected_codes, function(code) {
    idx = industry_code_match(df$industry_code, code)
    if (!any(idx)) return(df[0, , drop = FALSE])
    out = df[idx, , drop = FALSE]
    out$selected_code = code
    out
  })
  expanded
}

sanitize_api_error = function(txt, limit = 180) {
  clean = gsub("<[^>]*>", " ", as.character(txt))
  clean = gsub("[\r\n\t]+", " ", clean)
  clean = gsub("\\s+", " ", clean)
  clean = trimws(clean)
  substr(clean, 1, limit)
}

parse_mrts_month = function(x) {
  x = as.character(x)
  out = suppressWarnings(ym(x))
  idx_na = is.na(out)
  if (any(idx_na)) {
    x2 = gsub("([0-9]{4})M([0-9]{2})", "\\1-\\2", x[idx_na])
    out[idx_na] = suppressWarnings(ym(x2))
  }
  idx_na = is.na(out)
  if (any(idx_na)) {
    x3 = gsub("^([0-9]{4})([0-9]{2})$", "\\1-\\2", x[idx_na])
    out[idx_na] = suppressWarnings(ym(x3))
  }
  as.Date(out)
}

parse_census_rows = function(raw_json) {
  if (!is.list(raw_json) || length(raw_json) < 2) {
    return(tibble())
  }
  headers = unlist(raw_json[[1]])
  rows = raw_json[-1]
  mat = matrix(NA_character_, nrow = length(rows), ncol = length(headers))
  for (i in seq_along(rows)) {
    row_i = as.character(unlist(rows[[i]]))
    mat[i, seq_len(min(length(row_i), length(headers)))] = row_i[seq_len(min(length(row_i), length(headers)))]
  }
  df = as_tibble(as.data.frame(mat, stringsAsFactors = FALSE))
  names(df) = headers
  names(df) = tolower(gsub("[^a-zA-Z0-9]+", "_", names(df)))
  names(df) = make.unique(names(df), sep = "_")
  df
}

pick_col = function(df_names, exact = character(0), contains = character(0), exclude = character(0)) {
  nms = tolower(df_names)
  if (length(exact) > 0) {
    for (nm in tolower(exact)) {
      idx = which(nms == nm)
      if (length(idx) > 0) return(df_names[idx[1]])
    }
  }
  if (length(contains) > 0) {
    pat = paste(contains, collapse = "|")
    idx = grep(pat, nms)
    if (length(exclude) > 0) {
      ex_pat = paste(exclude, collapse = "|")
      idx = idx[!grepl(ex_pat, nms[idx])]
    }
    if (length(idx) > 0) return(df_names[idx[1]])
  }
  NA_character_
}

fetch_mrts_data = function(params) {
  endpoints = MRTS_ENDPOINTS
  industries = params$industries
  start_month = params$start_month
  end_month = params$end_month
  data_type = params$data_type
  api_key = Sys.getenv("CENSUS_API_KEY")

  if (!nzchar(api_key)) {
    stop("CENSUS_API_KEY is not set. Please run `Sys.setenv(CENSUS_API_KEY='your_key')` before Run Query.")
  }

  if (length(industries) == 0) {
    stop("No industry selected. Please choose at least one industry.")
  }
  if (start_month > end_month) {
    stop("Start month must be less than or equal to end month.")
  }

  start_year = as.integer(substr(start_month, 1, 4))
  end_year = as.integer(substr(end_month, 1, 4))
  years = as.character(seq(start_year, end_year))
  last_status = "Unknown MRTS query failure."

  fetch_one_year = function(endpoint, year_value) {
    query = list(
      get = "data_type_code,time_slot_id,seasonally_adj,category_code,cell_value,error_data",
      `for` = "us:*",
      time = year_value,
      seasonally_adj = "no",
      key = api_key
    )

    resp = try(httr::GET(endpoint, query = query, timeout(15)), silent = TRUE)
    if (inherits(resp, "try-error")) {
      return(list(
        ok = FALSE,
        message = glue("Request error at {endpoint} (time={year_value}): {as.character(resp)}"),
        data = tibble()
      ))
    }
    code = httr::status_code(resp)
    body_txt = httr::content(resp, "text", encoding = "UTF-8")
    if (code != 200) {
      return(list(
        ok = FALSE,
        message = glue("HTTP {code} at {endpoint} (time={year_value}): {sanitize_api_error(body_txt)}"),
        data = tibble()
      ))
    }
    parsed = try(jsonlite::fromJSON(body_txt, simplifyVector = FALSE), silent = TRUE)
    if (inherits(parsed, "try-error")) {
      return(list(ok = FALSE, message = "JSON parse failed.", data = tibble()))
    }
    df = parse_census_rows(parsed)
    if (nrow(df) == 0) {
      return(list(ok = FALSE, message = "No rows in response.", data = tibble()))
    }
    df$endpoint_used = endpoint
    df$time_query = year_value
    list(ok = TRUE, message = "", data = df)
  }

  df_raw = tibble()
  for (endpoint in endpoints) {
    yearly = map(years, ~ fetch_one_year(endpoint, .x))
    ok_rows = keep(yearly, ~ .x$ok)
    if (length(ok_rows) > 0) {
      df_raw = bind_rows(map(ok_rows, "data"))
      last_status = "OK"
      break
    } else if (length(yearly) > 0) {
      last_status = yearly[[length(yearly)]]$message
    }
  }

  if (nrow(df_raw) == 0) {
    stop(glue("API returned empty data for this query. Last status: {last_status}"))
  }

  period_col = pick_col(
    names(df_raw),
    exact = c("time_slot_date", "time", "month", "period", "time_slot_id"),
    contains = c("time_slot_date", "time", "month", "period", "time_slot_id")
  )
  value_col = pick_col(names(df_raw), exact = c("cell_value", "value", "sales"), contains = c("cell_value", "sales", "value"), exclude = c("error"))
  industry_col = pick_col(names(df_raw), exact = c("category_code", "cat_code", "naics", "industry_code"), contains = c("category", "cat_code", "naics", "industry"))
  dtype_col = pick_col(names(df_raw), exact = c("data_type_code", "data_type", "dt_code"), contains = c("data_type", "dt_code", "datatype"))
  seasonal_col = pick_col(names(df_raw), exact = c("seasonally_adj", "seasonal"), contains = c("season", "adjust"))

  if (is.na(period_col) || is.na(value_col) || is.na(industry_col)) {
    stop(glue(
      "Could not identify required columns from MRTS response. ",
      "Detected columns: {paste(names(df_raw), collapse=', ')}"
    ))
  }

  ind_map = tibble(industry_code = unname(MRTS_INDUSTRIES), industry = names(MRTS_INDUSTRIES))

  df = df_raw %>%
    mutate(
      month = parse_mrts_month(as.character(.data[[period_col]])),
      month_str = format(month, "%Y-%m"),
      value = suppressWarnings(as.numeric(gsub("[^0-9\\.-]", "", as.character(.data[[value_col]])))),
      industry_code = as.character(.data[[industry_col]])
    )

  # If selected period column fails, try using `time` column directly.
  if (all(is.na(df$month)) && "time" %in% names(df)) {
    df$month = parse_mrts_month(as.character(df$time))
    df$month_str = format(df$month, "%Y-%m")
  }

  # If period parsing still fails (e.g., time_slot_id carries month id with separate year), rebuild month.
  if (all(is.na(df$month)) && "time" %in% names(df) && "time_slot_id" %in% names(df)) {
    year_num = suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(df$time))))
    mon_num = suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(df$time_slot_id))))
    rebuilt = ifelse(
      !is.na(year_num) & !is.na(mon_num) & mon_num >= 1 & mon_num <= 12,
      sprintf("%04d-%02d", year_num, mon_num),
      NA_character_
    )
    df$month = as.Date(paste0(rebuilt, "-01"))
    df$month_str = format(df$month, "%Y-%m")
  }

  df = df %>%
    left_join(ind_map, by = "industry_code") %>%
    mutate(
      industry = if_else(is.na(industry), industry_code, industry),
      data_type = if (!is.na(dtype_col)) as.character(.data[[dtype_col]]) else "default",
      seasonally_adj = if (!is.na(seasonal_col)) as.character(.data[[seasonal_col]]) else "unknown"
    )

  available_codes = sort(unique(df$industry_code))
  selected_map = tibble(selected_code = unname(MRTS_INDUSTRIES), selected_label = names(MRTS_INDUSTRIES))

  df = expand_selected_industries(df, industries) %>%
    {
      if (!is.na(dtype_col) && !is.null(data_type) && data_type != "default") filter(., .data[[dtype_col]] == data_type) else .
    } %>%
    filter(!is.na(month), !is.na(value)) %>%
    filter(month >= as.Date(paste0(start_month, "-01")), month <= as.Date(paste0(end_month, "-01"))) %>%
    group_by(selected_code, month, month_str, data_type, seasonally_adj) %>%
    summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
    left_join(selected_map, by = "selected_code") %>%
    mutate(
      industry_code = selected_code,
      industry = if_else(is.na(selected_label), selected_code, selected_label)
    ) %>%
    select(industry_code, industry, month, month_str, data_type, seasonally_adj, value) %>%
    arrange(industry, month)

  if (nrow(df) == 0) {
    stop(glue(
      "Parsed data has no valid monthly values after cleaning. ",
      "Selected industry codes: {paste(industries, collapse = ', ')}. ",
      "Example available codes from API: {paste(head(available_codes, 12), collapse = ', ')}"
    ))
  }

  df
}

compute_summary_stats = function(df) {
  if (nrow(df) == 0) {
    return(list(
      total_rows = 0,
      date_range = c(NA_character_, NA_character_),
      per_industry = tibble(),
      notable_months = tibble()
    ))
  }

  per_industry = df %>%
    group_by(industry) %>%
    arrange(month, .by_group = TRUE) %>%
    summarise(
      rows = n(),
      mean = mean(value, na.rm = TRUE),
      min = min(value, na.rm = TRUE),
      max = max(value, na.rm = TRUE),
      first_value = first(value),
      last_value = last(value),
      pct_change = if_else(abs(first_value) < 1e-9, NA_real_, (last_value - first_value) / abs(first_value) * 100),
      volatility = sd(value, na.rm = TRUE),
      peak_month = month_str[which.max(value)],
      trough_month = month_str[which.min(value)],
      .groups = "drop"
    )

  notable_months = df %>%
    group_by(month_str) %>%
    summarise(total_value = sum(value, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(total_value))

  list(
    total_rows = nrow(df),
    date_range = c(format(min(df$month), "%Y-%m"), format(max(df$month), "%Y-%m")),
    per_industry = per_industry,
    notable_months = notable_months
  )
}

format_stats_for_prompt = function(stats) {
  per_industry_lines = stats$per_industry %>%
    mutate(
      line = glue(
        "- {industry}: mean={round(mean,2)}, min={round(min,2)}, max={round(max,2)}, ",
        "last={round(last_value,2)}, pct_change={round(pct_change,2)}%, volatility={round(volatility,2)}, ",
        "peak_month={peak_month}, trough_month={trough_month}"
      )
    ) %>%
    pull(line)

  notable = stats$notable_months %>%
    slice(c(1, n())) %>%
    mutate(line = glue("- {month_str}: total={round(total_value,2)}")) %>%
    pull(line)

  paste(
    glue("Total rows: {stats$total_rows}"),
    glue("Date range: {stats$date_range[1]} to {stats$date_range[2]}"),
    "Per-industry stats:",
    paste(per_industry_lines, collapse = "\n"),
    "Notable months (highest and lowest totals):",
    paste(notable, collapse = "\n"),
    sep = "\n"
  )
}

call_openai_report = function(prompt_text) {
  api_key = Sys.getenv("OPENAI_API_KEY")
  model = Sys.getenv("OPENAI_MODEL", "gpt-4o-mini")
  url = "https://api.openai.com/v1/chat/completions"

  if (!nzchar(api_key)) {
    stop("OPENAI_API_KEY is not set.")
  }

  body = list(
    model = model,
    messages = list(
      list(role = "system", content = "You are a precise business analyst writing concise, data-grounded reports."),
      list(role = "user", content = prompt_text)
    ),
    temperature = 0.2
  )

  resp = httr::POST(
    url,
    httr::add_headers(
      Authorization = paste("Bearer", api_key),
      `Content-Type` = "application/json"
    ),
    body = jsonlite::toJSON(body, auto_unbox = TRUE),
    encode = "raw",
    timeout(60)
  )

  if (httr::status_code(resp) != 200) {
    stop(glue("OpenAI request failed (HTTP {httr::status_code(resp)}): {httr::content(resp, 'text', encoding = 'UTF-8')}"))
  }

  out = jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (!is.null(out$error)) {
    err_msg = if (!is.null(out$error$message)) out$error$message else "Unknown error"
    stop(glue("OpenAI API error: {err_msg}"))
  }

  txt = NULL
  if (!is.null(out$choices) && length(out$choices) >= 1 && !is.null(out$choices[[1]]$message$content)) {
    txt = out$choices[[1]]$message$content
  } else if (!is.null(out$output_text)) {
    txt = out$output_text
  }

  if (is.null(txt)) {
    stop("OpenAI response missing text content.")
  }

  txt = paste(as.character(unlist(txt)), collapse = "\n")
  structure(txt, model_used = model, backend = "OpenAI")
}

call_ollama_report = function(prompt_text) {
  model = Sys.getenv("OLLAMA_MODEL")
  host = Sys.getenv("OLLAMA_HOST", "http://localhost:11434")

  if (!nzchar(model)) {
    stop("OLLAMA_MODEL is not set.")
  }

  ping = try(httr::GET(paste0(host, "/api/tags"), timeout(5)), silent = TRUE)
  if (inherits(ping, "try-error") || httr::status_code(ping) >= 400) {
    stop("Could not reach local Ollama endpoint. Set OLLAMA_HOST correctly and ensure `ollama serve` is running.")
  }

  body = list(
    model = model,
    prompt = paste(
      "You are a precise business analyst writing concise, data-grounded reports.",
      prompt_text,
      sep = "\n\n"
    ),
    stream = FALSE
  )

  resp = httr::POST(
    paste0(host, "/api/generate"),
    httr::add_headers(`Content-Type` = "application/json"),
    body = jsonlite::toJSON(body, auto_unbox = TRUE),
    encode = "raw",
    timeout(90)
  )

  if (httr::status_code(resp) != 200) {
    stop(glue("Ollama request failed (HTTP {httr::status_code(resp)}): {httr::content(resp, 'text', encoding = 'UTF-8')}"))
  }

  out = jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (!is.null(out$error)) {
    stop(glue("Ollama API error: {out$error}"))
  }

  txt = out$response
  if (is.null(txt) && !is.null(out$message$content)) {
    txt = out$message$content
  }
  if (is.null(txt)) {
    stop("Ollama response missing text content.")
  }

  txt = paste(as.character(unlist(txt)), collapse = "\n")
  structure(txt, model_used = model, backend = "Ollama")
}

generate_ai_report = function(stats, params) {
  stats_block = format_stats_for_prompt(stats)
  prompt = glue(
"Write a structured monthly retail report using ONLY the stats below.

Return exactly these sections:
1) Executive Summary (1 paragraph)
2) Key Findings (3-5 bullets)
3) Industry Comparison (who grew more, who is more volatile)
4) Notable Months / Seasonality (peak/trough months)
5) Data Notes (source, range, units, seasonal adjustment)

Selected industries: {paste(params$industry_labels, collapse = ', ')}
Date range requested: {params$start_month} to {params$end_month}
Data type selector: {params$data_type}
Endpoint: {params$endpoint}

Computed stats:
{stats_block}
"
  )

  if (nzchar(Sys.getenv("OPENAI_API_KEY"))) {
    return(call_openai_report(prompt))
  }

  if (nzchar(Sys.getenv("OLLAMA_MODEL"))) {
    return(call_ollama_report(prompt))
  }

  stop("AI is not configured. Set OPENAI_API_KEY, or set OLLAMA_MODEL and run a reachable Ollama server.")
}
