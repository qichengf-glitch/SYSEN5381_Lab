# 08_langchain/03_ollamar.R

# Check if ollamar package is installed
# has_ollamar = tryCatch(is.character(find.package("ollamar")), error = function(e){FALSE})
# if(!has_ollamar) { install.packages("ollamar") }

# Load packages
require(ollamar)
require(dplyr)
require(stringr)

# Select model of interest
# MODEL = "phi4-mini:3.8b"
MODEL = "smollm2:1.7b"


# Check if model is currently loaded
has_model = list_models() |> 
    filter(str_detect(name, MODEL)) |>
    nrow() > 0

# If model is not loaded, pull it
if(!has_model) { pull(MODEL) }

# resp = generate(MODEL, "Hello, how are you?")

# resp |> resp_process("text")

# messages = create_messages(
#     # Start system prompt
#     create_message(role = "system", content = "You are a talking mouse. Your name is Jerry. You can only talk about mice and cheese."),
#     # Add user prompt
#     create_message(role = "user", content = "Hello, how are you?")
# )

# system.time({
#     resp = chat(model = MODEL, messages = messages, output = "text", stream = FALSE)
# })
# # append result to chat history
# messages = append_message(x = messages, role = "assistant", content = resp)

add_two_numbers = function(x, y){
    return(x + y)
}

tool1 = list(
    type = "function",
    "function" = list(
        name = "add_two_numbers",
        description = "Add two numbers",
        parameters = list(
            type = "object",
            required = list("x", "y"),
            properties = list(
                x = list(type = "numeric", description = "first number"),
                y = list(type = "numeric", description = "second number")
            )
        )
    )
)

# Add a question to the chat history, meant to require the tool
# messages = append_message(x = messages, role = "user", content = "If I have 3 pieces of cheese, and you give me 2 more, how many pieces of cheese do I have?")

messages = create_message(role = "user", content = "What is 3 + 2?")
resp = chat(model = MODEL, messages = messages, tools = list(tool1), output = "tools", stream = FALSE)

# Receive back the tool call
tool = resp[[1]]
# Execute the tool call
do.call(tool$name, tool$arguments)



