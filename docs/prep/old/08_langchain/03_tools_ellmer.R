# 03_langchain_tools_ellmer.R

# Load packages
library(dplyr)
library(ellmer)

MODEL = "smollm2:1.7b"
# MODEL = "phi4-mini:3.8b"
PORT = 11434
OLLAMA_HOST = paste0("http://localhost:", PORT)


library(ellmer)
library(httr2)
library(jsonlite)

chat <- chat_ollama(model = MODEL, base_url = OLLAMA_HOST, system_prompt = "You are Yoda.")

chat$chat("Hello, how are you?")


#' Gets the current time in the given time zone.
#'
#' @param tz The time zone to get the current time in.
#' @return The current time in the given time zone.
get_current_time <- function(tz = "UTC") {
  format(Sys.time(), tz = tz, usetz = TRUE)
}

get_current_time <- tool(
  get_current_time,
  name = "get_current_time",
  description = "Returns the current time.",
  arguments = list(
    tz = type_string(
      "Time zone to display the current time in. Defaults to `\"UTC\"`.",
      required = FALSE
    )
  )
)

chat$register_tool(get_current_time)

chat$chat("How long ago did Neil Armstrong touch down on the moon?")