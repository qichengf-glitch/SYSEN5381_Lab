# 📌 ACTIVITY

## Your Project API Query

🕒 *Estimated Time: 20 minutes*

---

## ✅ Your Task

Set up secure API key storage and make your first successful query.

### 🧱 Stage 1: Get API Key (if needed)

- [ ] Register for an API key if required by your API
- [ ] Copy and keep your API key secure

### 🧱 Stage 2: Secure Storage

- [ ] Create `.env` file in `01_query_api` folder
- [ ] Add: `API_KEY=your_key_here` (use your API's variable name)
- [ ] Add `.env` to `.gitignore` (R: `usethis::use_git_ignore(".env")` or manually)
- [ ] Verify: `git status` should not show `.env`

### 🧱 Stage 3: First Query

**Python:**
- [ ] Install: `pip install python-dotenv`
- [ ] Create script that loads key from `.env` and makes a GET request
- [ ] Run and verify success (status code 200)

**R:**
- [ ] Create script using `readRenviron(".env")` to load key
- [ ] Make a GET request to your API
- [ ] Run and verify success (status code 200)

---

## 📤 To Submit

- For credit: Screenshot showing successful API response (status code and **data output**).

---

![](../docs/images/icons.png)

---

← 🏠 [Back to Top](#ACTIVITY)
