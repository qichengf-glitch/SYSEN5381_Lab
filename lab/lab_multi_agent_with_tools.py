# 0. SETUP ###################################

import csv
import json
import sys
import os
import requests

# Add the 08_function_calling folder to path so we can import functions.py
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "08_function_calling"))
from functions import agent_run

# Path to the BDS yearly aggregate CSV
DATA_PATH = os.path.join(os.path.dirname(__file__), "data", "pipeline", "bds_yearly_aggregate.csv")

# Model to use
MODEL = "smollm2:1.7b"

# 1. DEFINE CUSTOM TOOL FUNCTION ###################################

def get_bds_yearly_stats(year):
    """
    Look up total job creation value for a given year from the BDS yearly aggregate CSV.

    Parameters:
    -----------
    year : int or str
        The year to look up (e.g., 2019)

    Returns:
    --------
    str
        A summary string with the year and its total job creation value,
        or a message if the year is not found.
    """
    year = str(year)
    with open(DATA_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["YEAR"] == year:
                total = int(float(row["total_value"]))
                return f"In {year}, the total BDS job creation value was {total:,}."
    return f"No data found for year {year}."


# 2. DEFINE TOOL METADATA ###################################

tool_get_bds_yearly_stats = {
    "type": "function",
    "function": {
        "name": "get_bds_yearly_stats",
        "description": (
            "Look up the total job creation value for a specific year "
            "from the BDS (Business Dynamics Statistics) yearly aggregate dataset."
        ),
        "parameters": {
            "type": "object",
            "required": ["year"],
            "properties": {
                "year": {
                    "type": "integer",
                    "description": "The year to look up, e.g. 2019"
                }
            }
        }
    }
}

# 3. AGENT 1: FETCH DATA USING THE TOOL ###################################

print("=" * 50)
print("AGENT 1: Fetching BDS job creation data")
print("=" * 50)

# Agent 1 uses the tool to retrieve job creation stats for a specific year
from functions import agent

messages_agent1 = [
    {"role": "system", "content": "You are a data retrieval agent. Use the available tool to look up BDS job creation statistics for the year requested."},
    {"role": "user", "content": "What was the total BDS job creation value in 2019?"}
]

result_agent1 = agent(
    messages=messages_agent1,
    model=MODEL,
    output="text",
    tools=[tool_get_bds_yearly_stats]
)

print(f"Agent 1 output: {result_agent1}")
print()

# 4. AGENT 2: GENERATE ANALYSIS REPORT ###################################

print("=" * 50)
print("AGENT 2: Generating analysis report")
print("=" * 50)

# Agent 2 receives Agent 1's output and writes a short analytical report
result_agent2 = agent_run(
    role=(
        "You are an economic analyst. Given a data point about BDS job creation, "
        "write a brief 2-3 sentence analysis placing the number in context. "
        "Mention that BDS measures net job flows from firm births, deaths, expansions, and contractions."
    ),
    task=f"Here is the data retrieved: {result_agent1}\n\nWrite a short analysis of this finding.",
    model=MODEL
)

print(f"Agent 2 output:\n{result_agent2}")
print()

print("=" * 50)
print("WORKFLOW COMPLETE")
print("=" * 50)
