#!/bin/bash

# 02_rag.sh - Simple RAG with Ollama Gemma3
# A basic RAG system using text files and simple similarity
# 🛑🌐🤖📡🚀📚

# Load your local paths and variables
source .bashrc

# Configuration
PORT=11434  # Default Ollama port (change as needed)
export OLLAMA_HOST="0.0.0.0:$PORT"
MODEL="gemma3:latest"  # Your model
DOC="./02_query_ollama/docs/pokemon.csv"


# Create a sample document manually
# eg. 02_query_ollama/docs/pokemon.csv lists the base stats for all Pokemon
# https://gist.github.com/armgilles/194bcff35001e7eb53a2a8b441e8b2c6


# Create a searcher function
search() {
    local query="$1" # the first argument used in the function will be the query
    local document="$2" # the second argument will be the document to search
    # Search the file for the query word and return first 3 lines
    grep -i "$query" $DOC | head -3
}

search('Pikachu', '$DOC')


# Query Ollama with searcher function's results!
    local response=$(curl -s -X POST http://localhost:$PORT/api/generate \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'$MODEL'",
            "prompt": "'"$prompt"'",
            "stream": false
        }' 2>/dev/null)



# Function to query Ollama with context
query_with_context() {
    local query="$1"
    local context="$2"
    
    echo "Querying Ollama with context..."
    
    # Create prompt with context
    local prompt="Based on this information: $context

Question: $query

Please answer based on the information above:"

    
    
    # Extract response using jq
    echo "$response" | jq -r '.response'
}

# Main RAG function - simple version
rag_query() {
    local query="$1"
    echo "Processing RAG query: $query"
    
    # Find relevant text
    local relevant_text=$(find_relevant_text "$query")
    
    if [ -z "$relevant_text" ]; then
        echo "No relevant text found. Querying without context..."
        query_with_context "$query" "No relevant documents found."
    else
        echo "Found relevant text, querying with context..."
        query_with_context "$query" "$relevant_text"
    fi
}

# Test the system
echo "Testing RAG system..."
rag_query "What is machine learning?"

echo ""
echo "RAG system ready! You can now call: rag_query 'your question here'"
