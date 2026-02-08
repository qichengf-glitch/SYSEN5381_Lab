#' @name test_httr2.R
#' @title GET request with httr2
#' @description
#' Topic: API queries with httr2
#'
#' Makes a GET request to the GitHub API for the "octocat" user.
#' Demonstrates the basic httr2 workflow: request() -> req_perform() -> resp_*().

# 0. SETUP ###################################

## 0.1 Load Packages #################################

library(httr2)    # for HTTP requests
library(jsonlite) # optional: pretty-print or parse JSON

# 1. MAKE GET REQUEST ###################################

# Build the request: request() creates a GET by default when no body is set
req = request("https://api.github.com/users/octocat")

# Perform the request and store the response
resp = req_perform(req)

# 2. INSPECT RESPONSE ###################################

# HTTP status (200 = success)
resp$status_code

# Parse response body as R list (GitHub returns JSON)
resp_body_json(resp)

# Optional: get raw string or use jsonlite
# resp_body_string(resp)
# fromJSON(resp_body_string(resp))
