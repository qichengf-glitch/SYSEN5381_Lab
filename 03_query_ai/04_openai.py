# 04_openai.py
# Query OpenAI Models with API Key
# This script demonstrates how to query OpenAI's models
# using your API key stored in the .env file

# If you haven't already, install these packages...
# pip install requests python-dotenv

# Load libraries
import requests  # For HTTP requests
import json      # For working with JSON
import os        # For environment variables
from dotenv import load_dotenv  # For loading .env file

# Starting message
print("\n🚀 Querying OpenAI in Python...\n")

# Load environment variables from .env file
load_dotenv()

# Get API key from environment variable
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# Check if API key is set
if not OPENAI_API_KEY:
    raise ValueError("OPENAI_API_KEY not found in .env file. Please set it up first.")

# OpenAI API endpoint
url = "https://api.openai.com/v1/chat/completions"

# Construct the request body
body = {
    "model": "gpt-4o-mini",  # Low-cost model
    "messages": [
        {
            "role": "user",
            "content": "Hello! Please respond with: Model is working."
        }
    ]
}

# Set headers with API key
headers = {
    "Authorization": f"Bearer {OPENAI_API_KEY}",
    "Content-Type": "application/json"
}

# Send POST request to OpenAI API
response = requests.post(url, headers=headers, json=body)

# Check if request was successful
response.raise_for_status()

# Parse the response JSON
result = response.json()

# Extract the model's reply
output = result["choices"][0]["message"]["content"]

# Print the model's reply
print("📝 Model Response:")
print(output)
print()

# Closing message
print("✅ OpenAI query complete.\n")

# Clear environment
globals().clear()
