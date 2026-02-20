# 📌 ACTIVITY

## Set Up Ollama API Key

🕒 *Estimated Time: 5 minutes*

---

## ✅ Your Task

Set up your **Ollama** API key to query **Ollama Cloud** models. This allows you to use larger models that run on Ollama's servers instead of your local computer.

### 🔑 1. Get Your API Key

- [ ] Go to [ollama.com](https://ollama.com) and sign in or create an account
- [ ] Navigate to your account settings or **API keys** section
- [ ] Click **Create new secret key** or **Generate API key**
- [ ] Copy the API key immediately (you may not be able to see it again)
- [ ] Save it somewhere safe temporarily

### 💾 2. Store Your API Key

- [ ] In your project root directory, create a file named `.env` if it doesn't already exist
- [ ] Open the `.env` file in your text editor
- [ ] Add your API key in this format:

```
OLLAMA_API_KEY=your_api_key_here
```

- [ ] Save the `.env` file
- [ ] **Important**: Make sure `.env` is listed in your `.gitignore` file so you don't accidentally commit your API key to GitHub

### ✅ 3. Verify Setup

- [ ] Run the example script [`03_ollama_cloud.R`](03_ollama_cloud.R) or [`03_ollama_cloud.py`](03_ollama_cloud.py) to test your API key
- [ ] If the script runs successfully and you see a model response, your API key is configured correctly

---

## 📤 To Submit

- For credit: Upon completion, enter into the **CANVAS** assignment textbox entry a screenshot showing your `.env` file (with the API key line visible, but you can blur the actual key value for security).

---

![](../../docs/images/icons.png)

---

← 🏠 [Back to Top](#ACTIVITY)
