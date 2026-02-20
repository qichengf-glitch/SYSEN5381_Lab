# 📌 ACTIVITY

## Set Up OpenAI API Key

🕒 *Estimated Time: 5 minutes*

---

## ✅ Your Task

Set up your **OpenAI** API key to query **OpenAI** models. This allows you to use OpenAI's models like **GPT-4o-mini** (a low-cost option) for your projects.

### 🔑 1. Get Your API Key

- [ ] Go to [platform.openai.com](https://platform.openai.com) and sign in or create an account
- [ ] Navigate to **API keys** section (usually under your account settings)
- [ ] Click **Create new secret key**
- [ ] Give your key a name (e.g., "DSAI Course")
- [ ] Copy the API key immediately (you won't be able to see it again)
- [ ] Save it somewhere safe temporarily

### 💾 2. Store Your API Key

- [ ] In your project root directory, open the `.env` file (create it if it doesn't exist)
- [ ] Add your OpenAI API key in this format:

```
OPENAI_API_KEY=your_api_key_here
```

- [ ] Save the `.env` file
- [ ] **Important**: Make sure `.env` is listed in your `.gitignore` file so you don't accidentally commit your API key to GitHub

### 💰 3. Understanding Costs (IMPORTANT!)

- **GPT-4o-mini** is a low-cost model suitable for learning and testing
- OpenAI charges per token (input and output)
- Monitor your usage in the OpenAI dashboard to avoid unexpected charges
- Set up usage limits in your OpenAI account settings if desired

### ✅ 4. Verify Setup

- [ ] Run the example script [`04_openai.R`](04_openai.R) or [`04_openai.py`](04_openai.py) to test your API key
- [ ] If the script runs successfully, your API key is configured correctly

---

## 📤 To Submit

- For credit: Upon completion, enter into the **CANVAS** assignment textbox entry a screenshot showing your `.env` file (with the API key line visible, but you can blur the actual key value for security).

---

![](../../docs/images/icons.png)

---

← 🏠 [Back to Top](#ACTIVITY)
