# 02_rag.R

# How do I set up an LLM with Retrieval Augmented Generation in R?

# Load libraries
library(dplyr)
library(readr)
library(httr2)
library(jsonlite)
library(ollamar)
source("07_rag/functions.R")

MODEL = "smollm2:135m" # use this small model (no function calling, < 200 MB)
PORT = 11434 # use this default port
OLLAMA_HOST = paste0("http://localhost:", PORT) # use this default host
DOCUMENT = "07_rag/docs/pokemon.csv" # path to the document to search

# Define a search function we will operate programmatically
search = function(query, document){
    read_csv(document, show_col_types = FALSE) %>%
        filter(stringr::str_detect(Name, query)) %>%
        as.list() %>%
        jsonlite::toJSON(auto_unbox = TRUE) 
}

# Test search function
search("Pikachu", DOCUMENT)


# Suppose the user supplies a specific item to search
input = list(pokemon = "Pikachu")

# Task 1: Data Retrieval - Searchthe document for the item ------------
result1 = search(input$pokemon, DOCUMENT)

# Task 2: Generation augmented with the data retrieved - Generate a profile description of the Pokemon
role2 = "Output a short 200 word profile description of the Pokemon using the data provided by the user, written in markdown. Include a title, tagline, and notable stats."
result2 = agent_run(role = role2, task = result1, model = MODEL, output = "text")


# View result
result2

# Or, written manually using ollamar::chat
result2b = chat(
        model = MODEL,
    messages = list(
        list(role = "system", content = role2),
        list(role = "user", content = result1)
    ), output = "text", stream = FALSE)

# View result
result2b

