#!/usr/bin/env python3
# 05_embed.py
# Local semantic RAG with vector embeddings stored in SQLite
# Adapted for the SYSEN 5381 07_rag folder

import json
import math
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

import requests


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"
SOURCE_DB_PATH = DATA_DIR / "papers.db"
VECTOR_DB_PATH = DATA_DIR / "embed.db"
MODEL = "smollm2:1.7b"
# Prefer local helper functions from this folder.
sys.path.insert(0, str(SCRIPT_DIR))
from functions import agent_run


def tokenize(text):
    return re.findall(r"[a-z0-9]+", text.lower())


def build_idf(documents):
    doc_freq = Counter()
    for doc in documents:
        doc_freq.update(set(tokenize(doc["text"])))
    num_docs = len(documents)
    return {
        token: math.log((1 + num_docs) / (1 + freq)) + 1.0
        for token, freq in doc_freq.items()
    }


def tfidf_embed(text, idf):
    tokens = tokenize(text)
    counts = Counter(tokens)
    if not counts:
        return {}

    weights = {
        token: count * idf.get(token, 1.0)
        for token, count in counts.items()
    }
    norm = math.sqrt(sum(value * value for value in weights.values()))
    if norm == 0:
        return {}
    return {token: value / norm for token, value in weights.items()}


def cosine_similarity(vec_a, vec_b):
    if len(vec_a) > len(vec_b):
        vec_a, vec_b = vec_b, vec_a
    return sum(value * vec_b.get(token, 0.0) for token, value in vec_a.items())


def serialize_vector(vector):
    return json.dumps(vector, sort_keys=True)


def deserialize_vector(serialized):
    return json.loads(serialized)


def load_source_documents(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT id, title, content, category, author, tags
        FROM documents
        ORDER BY id
        """
    ).fetchall()
    conn.close()

    documents = []
    for row in rows:
        text = " ".join(
            value
            for value in [
                row["title"],
                row["category"] or "",
                row["tags"] or "",
                row["content"],
            ]
            if value
        )
        documents.append(
            {
                "id": row["id"],
                "title": row["title"],
                "category": row["category"] or "",
                "author": row["author"] or "",
                "content": row["content"],
                "text": text,
            }
        )
    return documents


def connect_vector_db(db_path=VECTOR_DB_PATH):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS embedded_documents (
            id INTEGER PRIMARY KEY,
            source_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            category TEXT,
            author TEXT,
            content TEXT NOT NULL,
            embedding TEXT NOT NULL
        )
        """
    )
    conn.commit()
    return conn


def build_index(conn, documents, idf):
    conn.execute("DELETE FROM embedded_documents")
    for doc in documents:
        conn.execute(
            """
            INSERT INTO embedded_documents
                (source_id, title, category, author, content, embedding)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                doc["id"],
                doc["title"],
                doc["category"],
                doc["author"],
                doc["content"],
                serialize_vector(tfidf_embed(doc["text"], idf)),
            ),
        )
    conn.commit()


def search_embed_sql(conn, query, idf, k=3):
    query_vector = tfidf_embed(query, idf)
    rows = conn.execute(
        """
        SELECT source_id, title, category, author, content, embedding
        FROM embedded_documents
        """
    ).fetchall()

    scored = []
    for row in rows:
        score = cosine_similarity(query_vector, deserialize_vector(row["embedding"]))
        scored.append(
            {
                "source_id": row["source_id"],
                "title": row["title"],
                "category": row["category"],
                "author": row["author"],
                "content": row["content"],
                "score": score,
            }
        )

    scored.sort(key=lambda item: item["score"], reverse=True)
    return scored[:k]


def _ollama_unreachable_message(exc):
    return (
        "[Skipped: could not reach Ollama at localhost. "
        "Start Ollama and pull the model, e.g. `ollama pull smollm2:1.7b`, then re-run.]\n"
        f"Details: {exc}"
    )


def format_context(results):
    blocks = []
    for item in results:
        excerpt = item["content"]
        if len(excerpt) > 500:
            excerpt = excerpt[:497] + "..."
        blocks.append(
            "\n".join(
                [
                    f"Title: {item['title']}",
                    f"Category: {item['category'] or 'Unknown'}",
                    f"Author: {item['author'] or 'Unknown'}",
                    f"Similarity: {item['score']:.3f}",
                    f"Content: {excerpt}",
                ]
            )
        )
    return "\n\n".join(blocks)


def extract_json_object(raw_text):
    text = raw_text.strip()
    if text.startswith("{") and text.endswith("}"):
        return text

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return ""


def normalize_answer(value):
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, str):
        text = value.strip().upper()
        if text in {"TRUE", "T", "YES"}:
            return "TRUE"
        if text in {"FALSE", "F", "NO"}:
            return "FALSE"
    return "TRUE"


def normalize_score(value, answer):
    if isinstance(value, str) and value.strip().isdigit():
        value = int(value.strip())
    if isinstance(value, (int, float)):
        score = int(round(value))
        if 1 <= score <= 5:
            return score
    return 5 if answer == "TRUE" else 1


def normalize_fact_check_output(raw_text, query, evidence_rows):
    evidence = [
        {
            "title": item["title"],
            "category": item["category"],
            "author": item["author"],
            "score": round(item["score"], 3),
        }
        for item in evidence_rows[:2]
    ]

    data = {}
    candidate = extract_json_object(raw_text)
    if candidate:
        try:
            data = json.loads(candidate)
        except json.JSONDecodeError:
            data = {}

    answer = normalize_answer(data.get("answer"))
    score = normalize_score(data.get("score"), answer)

    return {
        "query": data.get("query") or query,
        "answer": answer,
        "score": score,
        "evidence": data.get("evidence") or evidence,
    }


def deterministic_fact_check(query, evidence_rows):
    """
    Produce a stable fact-check result from retrieved evidence without relying on
    the generation model to return valid JSON.
    """
    stopwords = {
        "a",
        "an",
        "and",
        "are",
        "as",
        "by",
        "document",
        "for",
        "from",
        "in",
        "is",
        "it",
        "of",
        "on",
        "or",
        "that",
        "the",
        "this",
        "to",
        "with",
    }
    claim_terms = [token for token in tokenize(query) if token not in stopwords]
    evidence_text = " ".join(item["content"] for item in evidence_rows).lower()
    matched_terms = sorted({term for term in claim_terms if term in evidence_text})
    ratio = len(matched_terms) / len(claim_terms) if claim_terms else 0.0

    if ratio >= 0.85:
        answer = "TRUE"
        score = 5
    elif ratio >= 0.65:
        answer = "TRUE"
        score = 4
    elif ratio >= 0.45:
        answer = "FALSE"
        score = 3
    elif ratio >= 0.2:
        answer = "FALSE"
        score = 2
    else:
        answer = "FALSE"
        score = 1

    evidence = [
        {
            "title": item["title"],
            "category": item["category"],
            "author": item["author"],
            "score": round(item["score"], 3),
        }
        for item in evidence_rows[:3]
    ]
    return {
        "query": query,
        "answer": answer,
        "score": score,
        "matched_terms": matched_terms,
        "evidence": evidence,
    }


print("--------------------------------")
print("🔍 SEMANTIC SEARCH WORKFLOW:")
print("--------------------------------")

documents = load_source_documents(SOURCE_DB_PATH)
idf = build_idf(documents)
print(f"Loaded {len(documents)} source documents from {SOURCE_DB_PATH.name}.")

conn = connect_vector_db()
build_index(conn, documents, idf)
print(f"Built vector index in {VECTOR_DB_PATH.name}.\n")

print("--------------------------------")
print("🔍 PREVIEW EMBEDDED DOCUMENTS:")
print("--------------------------------")

preview = conn.execute(
    """
    SELECT source_id, title, category
    FROM embedded_documents
    ORDER BY source_id
    LIMIT 5
    """
).fetchall()
for row in preview:
    print((row["source_id"], row["title"], row["category"]))

print("\n--------------------------------")
print("🔍 TEST SEARCH:")
print("--------------------------------")

test_query = "How can I make SQL queries run faster?"
test_results = search_embed_sql(conn, test_query, idf, k=3)
for item in test_results:
    print(
        {
            "title": item["title"],
            "category": item["category"],
            "score": round(item["score"], 3),
        }
    )

print("\n--------------------------------")
print("🔍 RAG WORKFLOW:")
print("--------------------------------")

query = "What are good practices for writing readable Python code?"
result1 = search_embed_sql(conn, query, idf, k=3)
context = format_context(result1)
print(context)
print()

role = (
    "You are a helpful assistant that answers questions using only the retrieved context. "
    "Respond in markdown with a short title and bullet points. "
    "If the context is incomplete, say so clearly."
)
try:
    result2 = agent_run(role=role, task=f"Question: {query}\n\nContext:\n{context}", model=MODEL)
except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
    result2 = _ollama_unreachable_message(exc)
except requests.exceptions.HTTPError as exc:
    result2 = f"[Ollama returned an error. Is model `{MODEL}` installed?]\n{exc}"
print("📝 Generated Answer:")
print(result2)
print()

print("--------------------------------")
print("🔍 FACT-CHECKING WORKFLOW:")
print("--------------------------------")

fact_query = "The Python best practices document recommends following PEP 8 and writing docstrings."
fact_results = search_embed_sql(conn, fact_query, idf, k=3)
print("🧪 Fact Check:")
print(json.dumps(deterministic_fact_check(fact_query, fact_results), indent=2))

conn.close()
