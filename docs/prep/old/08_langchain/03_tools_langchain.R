# 03_langchain_tools.R

# How do I use LangChain to create a tool in R?

library(reticulate)
library(dplyr) # for starwars dataset
library(stringr) # for string operations

# Set up Python environment
reticulate::use_virtualenv("r-reticulate")

# Import required modules
langchain_tools = reticulate::import("langchain.tools")
langchain_agents = reticulate::import("langchain.agents")
langchain_ollama = reticulate::import("langchain_ollama.chat_models")

# Check what models are available

MODEL = "smollm2:1.7b"
# Create the Ollama chat model first
chat_model = langchain_ollama$ChatOllama(
  model = MODEL,
  base_url = "http://localhost:11434"
)

# Quick test (may take 5~10 seconds)
# chat_model$invoke("Hello, how are you?")


# Let's create a tool that searches the starwars dataset from the dplyr package.

# Define an R function that returns a string
search_starwars = function(query){
  paste0("Dunno who that is, but porgs are the best!")
}

# search_starwars = function(query){
#     # Testing value
#     # query = "Luke"
#     starwars = dplyr::starwars
#     result = starwars %>% 
#         filter(stringr::str_detect(name, pattern = query)) %>% 
#         as.list() %>% 
#         jsonlite::toJSON(auto_unbox = TRUE) %>%
#         as.character()
#     return(result)
# }


# Testing the function
search_starwars("Luke")

# Convert R function to Python tool using reticulate
tool_search_starwars = reticulate::py_call(
  langchain_tools$tool,
  name_or_callable = "search_starwars",
  description = "Search for information about a Star Wars character",
  runnable = reticulate::r_to_py(search_starwars)
)

# Now you can access the tool from R
tool_search_starwars


# Create the agent with the model and tools
agent = langchain_agents$create_agent(
  model = chat_model,
  tools = list(tool_search_starwars)
)

response = agent$invoke(list(
    messages = list(
        list(role = "user", content = "Who is Luke Skywalker?")
    )
))

cat(response$content)
