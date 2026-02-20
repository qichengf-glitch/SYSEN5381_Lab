#' @name bds_api.R
#' @title Helper: Fetch Census BDS (Business Dynamics Statistics) via API
#' @description
#' Functions to call the Census BDS timeseries API and return tidy data.
#' Used by the Shiny app to run the query on user request.
#' Expects dplyr (and thus %>%) to be loaded when this file is sourced.

# 0. CONFIG ###################################

API_BASE = "https://api.census.gov/data/timeseries/bds"

# 1. FETCH LOGIC ###################################

#' Fetch one year of BDS data from the Census API.
#' @param year Integer year (e.g. 2010).
#' @param metric Character, e.g. "JOB_CREATION".
#' @param geo_for Character, e.g. "us:1" or "state:*".
#' @param api_key Character, Census API key.
#' @return Data frame with one row per geography per year.
fetch_one_year = function(year, metric, geo_for, api_key) {
  resp = httr::GET(
    API_BASE,
    query = list(
      get   = metric,
      `for` = geo_for,
      YEAR  = year,
      key   = api_key
    )
  )
  if (!httr::http_error(resp)) {
    raw = jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"))

    # Get header (first row) and ncol — never use raw[1,] for names until df has ncol columns.
    if (is.list(raw) && !is.data.frame(raw)) {
      headers = as.character(unlist(raw[[1]]))
      ncol = length(headers)
      if (length(raw) < 2) {
        rows_mat = matrix(character(0), nrow = 0, ncol = ncol)
      } else {
        rows_mat = matrix(NA_character_, nrow = length(raw) - 1, ncol = ncol)
        for (i in seq_len(nrow(rows_mat))) {
          v = as.character(unlist(raw[[i + 1]]))
          rows_mat[i, seq_len(min(length(v), ncol))] = v[seq_len(min(length(v), ncol))]
        }
      }
    } else {
      raw = as.matrix(raw)
      headers = as.character(raw[1, ])
      ncol = length(headers)
      rows_mat = raw[-1, , drop = FALSE]
      if (nrow(rows_mat) > 0 && ncol(rows_mat) != ncol) {
        tmp = matrix(NA_character_, nrow = nrow(rows_mat), ncol = ncol)
        tmp[, seq_len(min(ncol(rows_mat), ncol))] = rows_mat[, seq_len(min(ncol(rows_mat), ncol))]
        rows_mat = tmp
      }
    }

    df = as.data.frame(rows_mat, stringsAsFactors = FALSE)
    names(df) = headers
    df$YEAR = year
    return(df)
  }
  # Return a clear error message for HTTP failures (e.g. 400, 403, 500).
  status = httr::status_code(resp)
  body = httr::content(resp, "text", encoding = "UTF-8")
  msg = if (nchar(body) > 200) paste0(substr(body, 1, 200), "...") else body
  stop(sprintf("Census API error (HTTP %d): %s", status, msg))
}

#' Fetch BDS time series for the given metric, geography, and year range.
#' @param metric Character, e.g. "JOB_CREATION".
#' @param geo_for Character, "us:1" or "state:*".
#' @param years Integer vector, e.g. 2010:2023.
#' @param api_key Character, Census API key.
#' @return Tidy data frame with YEAR, geography column(s), and metric column.
fetch_bds = function(metric, geo_for, years, api_key) {
  if (is.null(api_key) || is.na(api_key) || nchar(trimws(api_key)) == 0) {
    stop("CENSUS_API_KEY is missing. Set it in .Renviron or your system environment.")
  }

  df_all = purrr::map_dfr(years, function(y) {
    fetch_one_year(y, metric, geo_for, api_key)
  })

  if (nrow(df_all) == 0) {
    return(df_all)
  }

  df_all = df_all %>%
    dplyr::mutate(
      dplyr::across(dplyr::any_of(metric), ~ suppressWarnings(as.numeric(.x))),
      YEAR = as.integer(YEAR)
    ) %>%
    dplyr::select(dplyr::any_of(c("YEAR", "us", "state", metric))) %>%
    dplyr::arrange(YEAR)

  df_all
}
