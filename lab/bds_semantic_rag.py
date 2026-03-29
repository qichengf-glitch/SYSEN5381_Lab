import csv
import json
import math
import re
import sqlite3
from collections import Counter
from pathlib import Path

import requests


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data" / "pipeline"
VECTOR_DB_PATH = DATA_DIR / "embed.db"
CONTEXT_PATH = DATA_DIR / "bds_ai_context.txt"
SUMMARY_PATH = DATA_DIR / "task2_summary.txt"
YEARLY_TOTALS_PATH = DATA_DIR / "bds_yearly_aggregate.csv"
MODEL = "smollm2:1.7b"
PORT = 11434
OLLAMA_HOST = f"http://localhost:{PORT}"
CHAT_URL = f"{OLLAMA_HOST}/api/chat"


def agent_run(role, task, model=MODEL):
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": role},
            {"role": "user", "content": task},
        ],
        "stream": False,
    }
    response = requests.post(CHAT_URL, json=body, timeout=120)
    response.raise_for_status()
    return response.json()["message"]["content"]


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
    counts = Counter(tokenize(text))
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


def load_context_documents(path):
    text = path.read_text(encoding="utf-8")
    documents = []
    current_header = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.endswith(":") or line.startswith("Census BDS pipeline summary"):
            current_header = line.rstrip(":")
            continue
        title = current_header or "BDS context"
        documents.append(
            {
                "title": f"{title}",
                "category": "Context",
                "author": "Pipeline",
                "content": line,
                "text": f"{title} {line}",
            }
        )
    return documents


def load_summary_documents(path):
    text = path.read_text(encoding="utf-8")
    documents = []
    current_header = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.endswith(":"):
            current_header = line.rstrip(":")
            continue
        title = current_header or "Summary"
        documents.append(
            {
                "title": title,
                "category": "Summary",
                "author": "Pipeline",
                "content": line,
                "text": f"{title} {line}",
            }
        )
    return documents


def load_yearly_documents(path):
    documents = []
    with path.open(encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            year = row["YEAR"]
            total_value = int(float(row["total_value"]))
            content = f"Year {year} total job creation value is {total_value:,}."
            documents.append(
                {
                    "title": f"BDS yearly total {year}",
                    "category": "Yearly Aggregate",
                    "author": "BDS",
                    "content": content,
                    "text": f"{year} job creation total {total_value} yearly aggregate",
                }
            )
    return documents


def load_source_documents():
    documents = []
    documents.extend(load_context_documents(CONTEXT_PATH))
    documents.extend(load_summary_documents(SUMMARY_PATH))
    documents.extend(load_yearly_documents(YEARLY_TOTALS_PATH))
    return documents


def connect_vector_db(path=VECTOR_DB_PATH):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS embedded_documents (
            id INTEGER PRIMARY KEY,
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
            INSERT INTO embedded_documents (title, category, author, content, embedding)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                doc["title"],
                doc["category"],
                doc["author"],
                doc["content"],
                serialize_vector(tfidf_embed(doc["text"], idf)),
            ),
        )
    conn.commit()


def search_embed_sql(conn, query, idf, k=5):
    query_vector = tfidf_embed(query, idf)
    rows = conn.execute(
        """
        SELECT title, category, author, content, embedding
        FROM embedded_documents
        """
    ).fetchall()

    scored = []
    for row in rows:
        score = cosine_similarity(query_vector, deserialize_vector(row["embedding"]))
        scored.append(
            {
                "title": row["title"],
                "category": row["category"],
                "author": row["author"],
                "content": row["content"],
                "score": score,
            }
        )
    scored.sort(key=lambda item: item["score"], reverse=True)
    return scored[:k]


def format_context(results):
    blocks = []
    for item in results:
        blocks.append(
            "\n".join(
                [
                    f"Title: {item['title']}",
                    f"Category: {item['category']}",
                    f"Author: {item['author']}",
                    f"Similarity: {item['score']:.3f}",
                    f"Content: {item['content']}",
                ]
            )
        )
    return "\n\n".join(blocks)


def deterministic_fact_check(query, evidence_rows):
    stopwords = {
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "by",
        "in",
        "is",
        "it",
        "of",
        "on",
        "or",
        "the",
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


def ollama_error_message(exc):
    return (
        "[Skipped: could not reach Ollama at localhost. "
        "Start Ollama and pull the model, e.g. `ollama pull smollm2:1.7b`, then re-run.]\n"
        f"Details: {exc}"
    )


print("--------------------------------")
print("LAB SEMANTIC SEARCH WORKFLOW")
print("--------------------------------")

documents = load_source_documents()
idf = build_idf(documents)
print(f"Loaded {len(documents)} lab documents from {DATA_DIR}.")

conn = connect_vector_db()
build_index(conn, documents, idf)
print(f"Built vector index in {VECTOR_DB_PATH.name}.\n")

print("--------------------------------")
print("PREVIEW EMBEDDED DOCUMENTS")
print("--------------------------------")

preview = conn.execute(
    """
    SELECT title, category
    FROM embedded_documents
    LIMIT 5
    """
).fetchall()
for row in preview:
    print((row["title"], row["category"]))

print("\n--------------------------------")
print("TEST SEARCH")
print("--------------------------------")

test_query = "Which year had the highest total job creation?"
test_results = search_embed_sql(conn, test_query, idf, k=5)
for item in test_results:
    print(
        {
            "title": item["title"],
            "category": item["category"],
            "score": round(item["score"], 3),
        }
    )

print("\n--------------------------------")
print("RAG WORKFLOW")
print("--------------------------------")

query = (
    "Summarize the BDS job creation trend from 2010 to 2023 and identify "
    "which states or regions appear most important in the latest year."
)
result1 = search_embed_sql(conn, query, idf, k=5)
context = format_context(result1)
print(context)
print()

role = (
    "You are an analyst helping with a business dynamics dashboard project. "
    "Use only the retrieved context. "
    "Answer in markdown with a short title and flat bullet points. "
    "Summarize the trend, mention the latest-year leaders if present, and note any data limits."
)
try:
    result2 = agent_run(role=role, task=f"Question: {query}\n\nContext:\n{context}", model=MODEL)
except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
    result2 = ollama_error_message(exc)
except requests.exceptions.HTTPError as exc:
    result2 = f"[Ollama returned an error. Is model `{MODEL}` installed?]\n{exc}"
print("Generated Answer:")
print(result2)
print()

print("--------------------------------")
print("FACT-CHECKING WORKFLOW")
print("--------------------------------")

fact_query = "The highest annual total job creation value in the yearly aggregate occurs in 2022."
fact_results = search_embed_sql(conn, fact_query, idf, k=5)
print("Fact Check:")
print(json.dumps(deterministic_fact_check(fact_query, fact_results), indent=2))

conn.close()
