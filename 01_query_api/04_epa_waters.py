# 04_epa_waters.py
# Example of making an API request to EPA Waters API
# Based on: https://api.epa.gov/waters/v3/pointindexing

# This script shows how to:
# - Load an API key from a .env file
# - Make a GET request to the EPA Waters API
# - Inspect the HTTP status code and JSON response

# 0. Setup #################################

## 0.1 Load Packages ############################

# !pip install requests python-dotenv  # run this once in your environment

import os  # for reading environment variables
import requests  # for making HTTP requests
from dotenv import load_dotenv  # for loading variables from .env
import json  # for pretty printing JSON
import urllib.parse  # for URL encoding

## 0.2 Load Environment Variables ################

# Load environment variables from the .env file
load_dotenv(".env")

# Get the API key from the environment
EPA_API_KEY = os.getenv("EPA_API_KEY")

# Check if API key is loaded
if not EPA_API_KEY:
    print("ERROR: EPA_API_KEY not found in .env file!")
    print("Please create a .env file with: EPA_API_KEY=your_key_here")
    exit(1)

## 1. Make API Request ###########################

# Base URL for EPA Waters API
base_url = "https://api.epa.gov/waters/v3/pointindexing"

# Point coordinates (longitude, latitude)
# Example: Chicago area coordinates
point_coordinates = [-87.941093, 42.544354]

# Create the point JSON object
point_json = {
    "type": "Point",
    "coordinates": point_coordinates
}

# URL encode the point parameter
# Use separators to match exact format (no spaces in JSON)
point_encoded = urllib.parse.quote(json.dumps(point_json, separators=(',', ':')))

# Set up query parameters
# Note: p_point is already URL-encoded, so we build the URL manually
# to avoid double-encoding when using requests.get() with params=
other_params = {
    "p_indexing_engine": "DISTANCE",
    "p_limit_innetwork": "FALSE",
    "p_limit_navigable": "TRUE",
    "p_fallback_limit_innetwork": "FALSE",
    "p_fallback_limit_navigable": "TRUE",
    "p_return_link_path": "TRUE",
    "p_use_simplified_catchments": "FALSE",
    "p_network_resolution": "MR",
    "f": "json",
    "api_key": EPA_API_KEY
}

# Build the full URL manually to avoid double-encoding p_point
query_string = f"p_point={point_encoded}&" + urllib.parse.urlencode(other_params)
full_url = f"{base_url}?{query_string}"

# Set up headers
headers = {
    "accept": "application/json"
}

# Make the GET request
print("=== EPA Waters API - Point Indexing Query ===")
print(f"Querying point at coordinates: {point_coordinates}")
print(f"Status Code: ", end="")

response = requests.get(full_url, headers=headers)

## 2. Inspect Response ###########################

# View response status code (200 = success)
print(response.status_code)

if response.status_code == 200:
    # Extract the response as JSON
    data = response.json()
    
    # Pretty print the JSON response
    print("\n=== Response Data ===")
    print(json.dumps(data, indent=2))
    
    # You can also access specific fields from the response
    # Example: print(data.get('some_field', 'Field not found'))
else:
    print(f"\nError: {response.status_code}")
    print(response.text)
