# 📌 LAB

## Build an AI-Powered Data Reporter

🕒 *Estimated Time: 30 minutes*

---

## 📋 Lab Overview

Create a script that queries your API from [`LAB_your_good_api_query.md`](../01_query_api/LAB_your_good_api_query.md), processes the data, and uses AI (Ollama local/cloud or OpenAI) to generate a useful reporting summary. Iterate on your prompts to refine the output format and quality.

---

## ✅ Your Tasks

### Task 1: Prepare Data Pipeline

- [ ] Use your API query script from the previous lab (or create a new one)
- [ ] Process the API data: clean, filter, or aggregate as needed for reporting
- [ ] Format the processed data for AI consumption (e.g., JSON, CSV, or structured text)

### Task 2: Design Your AI Prompt

- [ ] Decide what you want the AI to return:
  - Summary statistics or insights?
  - Trends or patterns?
  - Recommendations or analysis?
  - Specific format (bullets, paragraphs, tables)?
- [ ] Write an initial prompt that includes your processed data and clear instructions
- [ ] Test with Ollama (local or cloud) or OpenAI using your example scripts

### Task 3: Iterate and Refine

- [ ] Run your script and review the AI output
- [ ] Refine your prompt based on results:
  - Adjust length requirements (e.g., "2-3 sentences" or "brief summary")
  - Specify format (e.g., "Use bullet points" or "Write in paragraph form")
  - Clarify what content to focus on
- [ ] Test 2-3 iterations until output is reliable and useful
- [ ] Write a couple sentences describing your process and why it works

---

## 💡 Tips and Resources

- **Prompt Design**: Be specific about format, length, and content focus. Examples: "Generate a 3-sentence summary" or "List the top 5 insights as bullet points"
- **Data Formatting**: Consider summarizing data before sending to AI to reduce token usage and improve focus
- **Iteration**: Start broad, then narrow down. Test what works and refine based on actual outputs
- **Example Scripts**: Reference [`02_ollama.py`](02_ollama.py), [`02_ollama.R`](02_ollama.R), [`03_ollama_cloud.py`](03_ollama_cloud.py), [`04_openai.py`](04_openai.py) for AI query patterns

---

## 📤 To Submit

- For credit: Submit:
  1. Your complete script (API query + data processing + AI reporting)
  2. Screenshot showing the final AI-generated report
  3. Brief explanation (2-3 sentences) of your prompt design choices and how you iterated to improve results

---

![](../docs/images/icons.png)

---

← 🏠 [Back to Top](#LAB)
