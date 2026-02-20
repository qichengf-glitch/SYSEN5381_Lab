#' @name task1_prepare_pipeline.R
#' @title Task 1 data pipeline for Census dashboard lab
#' @description
#' Pulls Census BDS API data, cleans/aggregates it, and exports AI-ready outputs
#' in CSV, JSON, and structured text formats.

# 0. SETUP ###################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
})

# Find bds_api.R whether run from shiny_app/ or from project root.
bds_path = "bds_api.R"
if (!file.exists(bds_path)) bds_path = "02_productivity/shiny_app/bds_api.R"
source(bds_path)

# 1. CONFIG ###################################

metric = Sys.getenv("BDS_METRIC", "JOB_CREATION")
geo_for = Sys.getenv("BDS_GEO_FOR", "state:*")
year_start = as.integer(Sys.getenv("BDS_YEAR_START", "2010"))
year_end = as.integer(Sys.getenv("BDS_YEAR_END", "2023"))
years = seq(year_start, year_end, by = 1)
api_key = Sys.getenv("CENSUS_API_KEY")

if (!nzchar(trimws(api_key))) {
  stop("CENSUS_API_KEY is missing. Set it in .Renviron or system environment.")
}

if (length(years) == 0 || any(is.na(years))) {
  stop("Invalid year range. Check BDS_YEAR_START and BDS_YEAR_END.")
}

output_dir = "02_productivity/shiny_app/data/pipeline"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# 2. FETCH + PROCESS ###################################

df_raw = fetch_bds(
  metric = metric,
  geo_for = geo_for,
  years = years,
  api_key = api_key
)

if (nrow(df_raw) == 0) {
  stop("No rows returned from Census API for the requested settings.")
}

# API returns either "state" (for state:*) or "us" (for us:1); ensure both exist for coalesce
if (!"state" %in% names(df_raw)) df_raw[["state"]] = NA_character_
if (!"us" %in% names(df_raw)) df_raw[["us"]] = NA_character_

df_clean = df_raw %>%
  mutate(
    geo_id = dplyr::coalesce(.data$state, .data$us),
    metric_value = as.numeric(.data[[metric]])
  ) %>%
  filter(!is.na(metric_value)) %>%
  select(YEAR, geo_id, metric_value)

df_yearly = df_clean %>%
  group_by(YEAR) %>%
  summarise(total_value = sum(metric_value, na.rm = TRUE), .groups = "drop") %>%
  arrange(YEAR)

latest_year = max(df_clean$YEAR, na.rm = TRUE)
df_latest_top = df_clean %>%
  filter(YEAR == latest_year) %>%
  arrange(desc(metric_value)) %>%
  slice_head(n = 10)

# 3. EXPORT ###################################

csv_clean_path = file.path(output_dir, "bds_clean.csv")
csv_yearly_path = file.path(output_dir, "bds_yearly_aggregate.csv")
json_path = file.path(output_dir, "bds_ai_payload.json")
txt_path = file.path(output_dir, "bds_ai_context.txt")

write_csv(df_clean, csv_clean_path)
write_csv(df_yearly, csv_yearly_path)

payload = list(
  metadata = list(
    source = "US Census BDS API",
    metric = metric,
    geography = geo_for,
    years = list(start = year_start, end = year_end),
    rows_clean = nrow(df_clean)
  ),
  yearly_aggregate = df_yearly,
  top_10_latest_year = df_latest_top
)

write_json(payload, json_path, pretty = TRUE, auto_unbox = TRUE)

lines = c(
  "Census BDS pipeline summary",
  paste0("Metric: ", metric),
  paste0("Geography selector: ", geo_for),
  paste0("Year range: ", year_start, "-", year_end),
  paste0("Clean rows: ", nrow(df_clean)),
  "",
  "Yearly totals:",
  paste0(df_yearly$YEAR, ": ", format(round(df_yearly$total_value, 2), big.mark = ",")),
  "",
  paste0("Top 10 geographies in latest year (", latest_year, "):"),
  paste0(df_latest_top$geo_id, ": ", format(round(df_latest_top$metric_value, 2), big.mark = ","))
)
writeLines(lines, txt_path)

message("Pipeline complete. Files saved:")
message("- ", csv_clean_path)
message("- ", csv_yearly_path)
message("- ", json_path)
message("- ", txt_path)
