# 02_demo.R

# How do I use LangChain in R?

library(reticulate)

# Example using miniconda
# reticulate::install_miniconda()
# Or create a virtual environment
# reticulate::virtualenv_create("r-reticulate")
reticulate::use_virtualenv("r-reticulate")

# Install langchain
# reticulate::py_install("langchain")
# You might also need specific integrations, e.g., for Ollama
# reticulate::py_install("langchain-ollama")

# Import langchain package
langchain <- reticulate::import("langchain")

# Load in the ChatOllama class
ChatOllama = reticulate::import("langchain_ollama.chat_models")$ChatOllama

# Create a chat model instance
chat_model = ChatOllama(model = "smollm:135m", base_url = "http://localhost:11434")


# Construct the message as a list of lists
messages = list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = "Explain the concept of quantum entanglement.")
)
# View the messages
messages

# Invoke the chat model, passing in the messages
response = chat_model$invoke(messages)

# Print the response
cat(response$content)


# Clean up shop
rm(list = ls())