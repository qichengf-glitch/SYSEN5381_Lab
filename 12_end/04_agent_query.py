# 04_agent_query.py
# Agent with REST Tool Call
# Pairs with 04_agent_query.R
# Tim Fraser

import sys
import os
import json
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]

from dotenv import load_dotenv
import requests

# 1. CONFIG ###################################

load_dotenv(ROOT_DIR / "12_end" / ".env")

ENDPOINT_URL = os.getenv("API_PUBLIC_URL", "http://localhost:8000").rstrip("/")
MODEL       = os.getenv("OLLAMA_MODEL",   "nemotron-3-nano:30b-cloud")
OLLAMA_HOST = os.getenv("OLLAMA_HOST",    "https://ollama.com").rstrip("/")
OLLAMA_KEY  = os.getenv("OLLAMA_API_KEY", "")
CHAT_URL    = f"{OLLAMA_HOST}/api/chat"


def agent(messages, model=MODEL, output="text", tools=None):
    """Minimal Ollama cloud agent with one-shot tool-calling support."""
    body = {"model": model, "messages": messages, "stream": False}
    if tools:
        body["tools"] = tools
    headers = {"Content-Type": "application/json"}
    if OLLAMA_KEY:
        headers["Authorization"] = f"Bearer {OLLAMA_KEY}"

    resp = requests.post(CHAT_URL, json=body, headers=headers, timeout=60)
    resp.raise_for_status()
    result = resp.json()
    msg = result.get("message", {})

    tool_calls = msg.get("tool_calls", [])
    if tools and tool_calls:
        tc = tool_calls[0]
        fn_name = tc["function"]["name"]
        raw_args = tc["function"]["arguments"]
        fn_args = raw_args if isinstance(raw_args, dict) else json.loads(raw_args)
        # resolve the tool function from the calling script
        import __main__
        fn = getattr(__main__, fn_name, None)
        tool_output = fn(**fn_args) if fn else {"error": "unknown tool"}
        if output == "text":
            return tool_output
        return tool_calls
    return msg.get("content", "")

UNIT_NOTE = "vehicles observed in one representative minute (1m/t1 interval) within the requested hour and day of week"

# 2. DEFINE TOOL FUNCTION ###################################

def predict_vehicle_count(day_of_week, hours_of_day):
    hours = [int(h) for h in hours_of_day if 0 <= int(h) <= 23]
    if not hours:
        raise ValueError("hours_of_day must contain at least one integer between 0 and 23.")

    predictions = []
    for hour in hours:
        resp = requests.get(
            f"{ENDPOINT_URL}/predict",
            params={"day_of_week": int(day_of_week), "hour_of_day": hour},
            timeout=10,
        )
        resp.raise_for_status()
        predictions.append(
            {
                "hour_of_day": hour,
                "predicted_vehicle_count": float(resp.json()["predicted_vehicle_count"]),
            }
        )

    return {
        "day_of_week": int(day_of_week),
        "unit": "vehicles_observed_in_one_minute",
        "interval": "1m_t1",
        "note": "Each prediction is for one representative minute within that hour and day of week.",
        "predictions": predictions,
    }

# 3. DEFINE TOOL METADATA ###################################

tool_predict_vehicle_count = {
    "type": "function",
    "function": {
        "name": "predict_vehicle_count",
        "description": (
            "Predict Brussels vehicle count for a specific day of week and vector of hours. "
            "Returns one estimated vehicle count per requested hour. "
            "Each value is for one representative minute (1m/t1 interval) within that hour on that day of week."
        ),
        "parameters": {
            "type": "object",
            "required": ["day_of_week", "hours_of_day"],
            "properties": {
                "day_of_week": {"type": "integer", "description": "Day of week (1=Monday, ..., 7=Sunday)"},
                "hours_of_day": {
                    "type": "array",
                    "description": "Vector of hours to predict (0-23), e.g. [0,1,2,...,23].",
                    "items": {"type": "integer"},
                },
            }
        }
    }
}

# 4. RUN AGENT ###################################

messages = [
    {
        "role": "system",
        "content": (
            "You are a Brussels traffic assistant. "
            "Always report units clearly as vehicles observed in one representative minute "
            "(1m/t1 interval) within the requested hour and day of week. "
            "Call predict_vehicle_count using day_of_week and hours_of_day vector."
        ),
    },
    {
        "role": "user",
        "content": "Predict Brussels vehicle count for Monday at 8 AM.",
    }
]
tools = [tool_predict_vehicle_count]

result = agent(
    messages=messages,
    model=MODEL,
    output="text",
    tools=tools
)

print("Agent result:", result)

# 5. VERIFY ###################################

direct = predict_vehicle_count(day_of_week=1, hours_of_day=[8])
print("Direct API call predictions returned:", len(direct["predictions"]))
print(f"Sample one-minute vehicle count: {direct['predictions'][0]['predicted_vehicle_count']} (1m/t1 at Monday 08:00)")
print("Unit:", UNIT_NOTE)
