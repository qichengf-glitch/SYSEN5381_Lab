# 08_langchain/functions.R

# We're going to design a set of functions to approximate langchain's multi-agent orchestration in R, building on the ollamar package.

# required packages
library(ollamar)
library(dplyr)
library(stringr)

# Ultra-Simple Multi-Agent System
library(ollamar)
library(dplyr)

# 1. Define agents (just names and roles)
agents = c("researcher", "analyzer", "writer")
roles = c("I find information", "I analyze data", "I write reports")

# 2. Simple workflow (just a sequence)
workflow = c("researcher", "analyzer", "writer")

# 3. Run one agent
run_agent = function(agent_name, task) {
  role = roles[agents == agent_name]
  
  messages = create_messages(
    create_message(role = "system", content = role),
    create_message(role = "user", content = task)
  )
  
  response = chat(model = "smollm2:1.7b", messages = messages, output = "text", stream = FALSE)
  return(response)
}

# 4. Run simple workflow
run_simple_workflow = function(task, nmax = 50) {
  results = list()
  
  for (agent in workflow) {
    cat("Running", agent, "...\n")
    result = run_agent(agent, task)
    print(result)
    results[[agent]] = result
    cat("Done!\n\n")
    
    # Next task is to process the result
    task = paste("Process this:", str_trunc(result, nmax))
  }
  
  return(results)
}

# 5. Use it
results = run_simple_workflow("Tell me about renewable energy")
