# 📌 ACTIVITY

## Deploy to Posit Connect with GitHub Actions

🕒 *Estimated Time: 20-30 minutes*

---

## ✅ Your Task

Set up GitHub Actions to automatically deploy your app/API to Posit Connect when you push code to `main`.

### 🧱 Stage 1: Build `manifest.json`

A `manifest.json` file tells Posit Connect what dependencies and versions are required by your app/API.

Run the matching template script:

- Shiny R app:
  `Rscript 04_deployment/positconnect/shinyr/manifestme.R <path-to-app-folder>`
- Plumber API (R):
  `Rscript 04_deployment/positconnect/plumber/manifestme.R <path-to-api-folder>`
- Shiny for Python app:
  `bash 04_deployment/positconnect/shinypy/manifestme.sh <path-to-app-folder>`
- FastAPI (Python):
  `bash 04_deployment/positconnect/fastapi/manifestme.sh <path-to-api-folder> [entrypoint]`

Example for this repository (Shiny R app in `lab/`):

```bash
Rscript 04_deployment/positconnect/shinyr/manifestme.R lab
```

### ⚙️ Stage 2: Configure GitHub Actions

This repository includes:

- Workflow file:
  `.github/workflows/deploy-posit-connect.yml`

Add these repository secrets in GitHub:

- `CONNECT_SERVER` (e.g., `https://your-connect-server.example.com`)
- `CONNECT_ACCOUNT` (your Posit Connect account/publisher name)
- `CONNECT_API_KEY`
- `CONNECT_API_SECRET`

Optional repository variables:

- `POSIT_APP_DIR` (default is `lab`)
- `CONNECT_APP_NAME` (if you want a fixed app name on Connect)

### 🚀 Stage 3: Deploy by pushing code

1. Commit your changes (including `manifest.json` in your app folder).
2. Push to `main`.
3. Open GitHub Actions and verify the workflow run:
   `Deploy to Posit Connect`.

If needed, you can also trigger deployment manually using `workflow_dispatch`.

---

## 📤 To Submit

- A successful GitHub Actions run of `Deploy to Posit Connect`
- Your deployed Posit Connect app/API URL

---

![](../../docs/images/icons.png)

---

← 🏠 [Back to Top](#ACTIVITY)
