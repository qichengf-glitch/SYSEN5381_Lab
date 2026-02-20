#' @name lab1.R
#' @title Fetch BDS (Business Dynamics Statistics) from Census API
#' @description
#' Topic: API query – Census BDS timeseries
#'
#' Fetches job creation (or other BDS metrics) from the Census API for chosen
#' geography and years, then saves a tidy CSV for use in a Shiny app or analysis.

# 0. SETUP ###################################

## 0.1 Load Packages #################################

library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(readr)
library(tidyr)

## 0.2 API Configuration ####################################

API_BASE = "https://api.census.gov/data/timeseries/bds"
API_KEY  = Sys.getenv("CENSUS_API_KEY")

if (API_KEY == "") {
  stop("CENSUS_API_KEY is missing. Set it in .Renviron or your system environment.")
}

# ---- Choose a metric (you can change later) ----
# Common examples in BDS docs include JOB_CREATION.
METRIC = "JOB_CREATION"

# ---- Choose geography ----
# US total:
geo_for = "us:1"

# For state-level comparisons, use: geo_for = "state:*"

# ---- Years to pull (time series) ----
years = 2010:2023

# 1. FETCH DATA ###################################

# Fetch one year of BDS data and return a data frame.
fetch_one_year = function(y) {
  resp = GET(
    API_BASE,
    query = list(
      get   = METRIC,
      `for` = geo_for,
      YEAR  = y,
      key   = API_KEY
    )
  )
  stop_for_status(resp)

  raw = fromJSON(content(resp, "text", encoding = "UTF-8"))
  df = as.data.frame(raw[-1, ], stringsAsFactors = FALSE)
  names(df) = raw[1, ]
  df$YEAR = y
  df
}

df_all = map_dfr(years, fetch_one_year) %>%
  mutate(
    across(all_of(METRIC), ~ suppressWarnings(as.numeric(.x))),
    YEAR = as.integer(YEAR)
  )

# Keep only useful columns (YEAR, us or state, and the metric).
df_tidy = df_all %>%
  select(any_of(c("YEAR", "us", "state", METRIC))) %>%
  arrange(YEAR)

# 2. SAVE OUTPUT ###################################

dir.create("02_productivity/shiny_app/data", recursive = TRUE, showWarnings = FALSE)
write_csv(df_tidy, "02_productivity/shiny_app/data/bds_timeseries.csv")

message("Saved: 02_productivity/shiny_app/data/bds_timeseries.csv")
