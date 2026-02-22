# Test script to diagnose MRTS API issues
# Run this to check if the API is accessible

library(httr)
library(jsonlite)

# Check API key
api_key = Sys.getenv("CENSUS_API_KEY")
cat("CENSUS_API_KEY status:", if (nzchar(api_key)) "SET" else "NOT SET", "\n\n")

# Test endpoints
endpoints = c(
  "https://api.census.gov/data/timeseries/mrts",
  "https://api.census.gov/data/timeseries/eits/mrts"
)

for (endpoint in endpoints) {
  cat("Testing endpoint:", endpoint, "\n")
  
  # Try a simple query
  query = list(
    get = "time,category_code,cell_value",
    `for` = "us:*",
    time = "2020"
  )
  if (nzchar(api_key)) query$key = api_key
  
  resp = try(httr::GET(endpoint, query = query, timeout(10), verbose = TRUE), silent = TRUE)
  
  if (inherits(resp, "try-error")) {
    cat("  ERROR: Request failed -", as.character(resp), "\n\n")
    next
  }
  
  code = httr::status_code(resp)
  cat("  Status code:", code, "\n")
  
  if (code == 200) {
    body = httr::content(resp, "text", encoding = "UTF-8")
    parsed = try(jsonlite::fromJSON(body, simplifyVector = FALSE), silent = TRUE)
    if (!inherits(parsed, "try-error") && length(parsed) > 0) {
      cat("  SUCCESS: Got", length(parsed) - 1, "rows\n")
      cat("  Columns:", paste(parsed[[1]], collapse = ", "), "\n\n")
    } else {
      cat("  WARNING: Response is not valid JSON\n\n")
    }
  } else {
    body = httr::content(resp, "text", encoding = "UTF-8")
    cat("  ERROR:", substr(body, 1, 200), "\n\n")
  }
}

cat("\nIf all endpoints return 404, the API endpoints may have changed.\n")
cat("Check: https://www.census.gov/data/developers/data-sets.html\n")
