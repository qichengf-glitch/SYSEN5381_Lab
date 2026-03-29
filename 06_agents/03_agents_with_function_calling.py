# 03_agents_with_function_calling.py
# Agent Wrapper with Function Calling
# Tim Fraser / SYSEN 5381

# This script demonstrates:
# - Stage 1: How agent() handles both standard chat and tool calls
# - Stage 2: Adding a new tool (calculate_average) with tool metadata

# 0. SETUP ###################################

import json
from functions import agent, agent_run, get_shortages, df_as_text

MODEL = "smollm2:135m"

# =============================================================================
# STAGE 1: REVIEW AGENT WRAPPER
# =============================================================================
# The agent() function in functions.py has two modes:
#
#   Mode A (no tools): sends a plain chat request to Ollama
#     -> agent(messages, model)
#     -> returns a text string (the model's reply)
#
#   Mode B (with tools): sends a function-calling request to Ollama
#     -> agent(messages, model, tools=[...])
#     -> model decides which tool to call and with what args
#     -> agent() executes the matching Python function automatically
#     -> returns the tool's output (not the model's text)
#
# Key difference: passing `tools` switches the entire request path.

# -- Demo: Standard chat (no tools) --
print("=" * 60)
print("STAGE 1A: Standard chat (no tools)")
print("=" * 60)

messages_chat = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user",   "content": "What is a drug shortage in one sentence?"}
]

response_chat = agent(messages=messages_chat, model=MODEL)
print("Response:", response_chat)

# =============================================================================
# STAGE 2: ADD A NEW TOOL — calculate_average()
# =============================================================================

# -- 2.1 Define the Python function --

def calculate_average(numbers: list) -> float:
    """Calculate the arithmetic mean of a list of numbers."""
    if not numbers:
        return 0.0
    return sum(numbers) / len(numbers)

# -- 2.2 Define tool metadata (Ollama / OpenAI-compatible JSON Schema) --

tools = [
    {
        "type": "function",
        "function": {
            "name": "calculate_average",
            "description": "Calculate the arithmetic mean (average) of a list of numbers.",
            "parameters": {
                "type": "object",
                "properties": {
                    "numbers": {
                        "type": "array",
                        "items": {"type": "number"},
                        "description": "A list of numeric values to average."
                    }
                },
                "required": ["numbers"]
            }
        }
    }
]

# -- 2.3 Test the new tool with the agent wrapper --

print("\n" + "=" * 60)
print("STAGE 2: Tool calling — calculate_average()")
print("=" * 60)

# Pull real data: drug shortage counts by generic name (Psychiatry)
data = get_shortages(category="Psychiatry", limit=500)

# Count shortages per drug name and collect counts as a list
counts = (
    data.groupby("generic_name")
        .size()
        .reset_index(name="count")
)

number_list = counts["count"].tolist()
print(f"Shortage counts per drug (first 10): {number_list[:10]} ...")

# Ask the agent to use the calculate_average tool
messages_tool = [
    {
        "role": "system",
        "content": "You are a data analyst. Use the calculate_average tool when asked to compute an average."
    },
    {
        "role": "user",
        "content": (
            f"Here are shortage counts per drug: {number_list}. "
            "Please calculate the average number of shortages per drug."
        )
    }
]

result = agent(messages=messages_tool, model=MODEL, tools=tools)
print(f"\nAverage shortages per drug (tool output): {result}")

# -- 2.4 Verify by computing directly in Python --
direct = calculate_average(number_list)
print(f"Direct Python check:                    {direct:.4f}")
