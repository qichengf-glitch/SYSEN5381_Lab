# Quick test - run this in R console
# Load environment
if (file.exists(".Renviron")) readRenviron(".Renviron")

# Check API key
cat("CENSUS_API_KEY:", if (nzchar(Sys.getenv("CENSUS_API_KEY"))) "SET" else "NOT SET", "\n")

# Simple API test
library(httr)
endpoint = "https://api.census.gov/data/timeseries/mrts"
query = list(
  get = "time,category_code,cell_value",
  `for` = "us:*",
  time = "2020",
  key = Sys.getenv("CENSUS_API_KEY")
)

cat("\nTesting endpoint:", endpoint, "\n")
resp = httr::GET(endpoint, query = query, timeout(10))
cat("Status:", httr::status_code(resp), "\n")

if (httr::status_code(resp) == 200) {
  cat("SUCCESS! API is working.\n")
} else {
  cat("Error:", substr(httr::content(resp, "text"), 1, 200), "\n")
}
