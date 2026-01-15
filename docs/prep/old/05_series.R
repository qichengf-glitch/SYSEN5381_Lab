# 05_series.R

# This script demonstrates how to use the agent() function to build a workflow, 
# using an as-simple-as-possible imitation of LangChain's multi-agent orchestration

# Load packages
require(ollamar)
require(dplyr)
require(stringr)

# Select model of interest
MODEL = "smollm2:1.7b"

# We're going to design an archetypal series workflow for agents.


# =============================================================================
# SERIES AGENTS (Sequential Processing)
# =============================================================================


run_agent = function(agent_name, task, model = "smollm2:1.7b", output = "text",tools = NULL, agents_series = "researcher", roles_series = "I find information") {

  # Testing values
  # Simple sequential workflow - agents run one after another
    # agents_series = c("researcher", "analyzer", "writer")
    # roles_series = c("I find information", "I analyze data", "I write reports")


  # Define the role of the agent
  role = roles_series[agents_series == agent_name]
  
  # Define the messages to be sent to the agent
  messages = create_messages(
    create_message(role = "system", content = role),
    create_message(role = "user", content = task)
  )
  
  # Run the agent
  resp = agent(messages = messages, model = model, output = output, tools = tools, all = FALSE)
  
  # Print success message
  cat("✅", agent_name, "completed\n\n")

  # Return the response from the agent
  return(resp)
}








# You define your series workflow by defining the agents and the roles.
workflow_series = function(task, nmax = 500) {
  cat("🔄 SERIES WORKFLOW: Agents run sequentially\n")
  # Check that the task is not empty
  stopifnot(length(task) > 0)

   # Define the agents and roles for the workflow
   #  Simple sequential workflow - agents run one after another
   agents_series = c("researcher", "analyzer", "writer")
   roles_series = c("I find information", "I analyze data", "I write reports")


  # Initialize the results list
  results = list()

  
  # Get the number of steps in the workflow
  max_steps = length(task)  

  # Get the task for the current step
  task_i = task[1]

  # Loop through the agents
  for (i in 1:max_steps) {
    # i = 1
    agent_i = agents_series[i]
    cat("Step", i, "- Running", agent_i, "...\n")

    result = run_agent(agent_name = agent_i, task = task_i, model = MODEL, output = "text", tools = NULL)
    results[[agent_i]] = result
    cat("✅", agent_i, "completed\n\n")
    
    # Pass result to next agent
    # Truncate the result to the maximum number of characters
    task_i = paste("Process this:", str_trunc(result, nmax))
  }
  
  return(results)
}


x = workflow_series(task = c("Tell me about solar energy in 100 words or less."), nmax = 500)