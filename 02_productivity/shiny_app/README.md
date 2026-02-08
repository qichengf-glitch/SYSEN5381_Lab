# Census BDS Shiny App

Shiny app that runs the **Census BDS (Business Dynamics Statistics) API** query on demand: choose metric, geography, and years, then view results in a table and time series plot.

---

## Overview

This app implements the API logic from [`lab1.R`](../../01_query_api/lab1.R). It:

- **Fetches on request** — Data is loaded only when you click **Fetch from API** (no automatic calls).
- **Lets you choose** — **Metric** (e.g. JOB_CREATION, JOB_DESTRUCTION), **Geography** (US total or all states), and **Year range** (slider).
- **Shows results** — **Table** tab (paginated data table) and **Time series** tab (line plot). For state-level data, the plot shows the US total by year.
- **Handles errors** — Clear message if the API key is missing or the request fails. Sidebar shows **API key: set** or **API key: not set**.

---

## Installation

### 1. Install R packages

From the `shiny_app` folder in R or in the shell:

```r
# In R (from 02_productivity/shiny_app):
source("install_deps.R")
```

Or in the shell (from project root):

```bash
Rscript 02_productivity/shiny_app/install_deps.R
```

Or install manually in R:

```r
install.packages(c("shiny", "bslib", "DT", "httr", "jsonlite", "dplyr", "purrr", "readr", "tidyr", "ggplot2"))
```

### 2. Set your Census API key

- Get a key: [Census API Key Request](https://api.census.gov/data/key_signup.html).
- Put it in your environment. For example, in the project root file [`.Renviron`](../../.Renviron):

  ```
  CENSUS_API_KEY=your_key_here
  ```

- Restart R (or run `readRenviron(".Renviron")` or `readRenviron("~/.Renviron")`) so the key is loaded.

---

## How to run

From R, **from the project root** (`dsai`):

```r
shiny::runApp("02_productivity/shiny_app")
```

Or from the `shiny_app` folder:

```r
setwd("02_productivity/shiny_app")
shiny::runApp()
```

The app will open in your browser. Stop it with **Esc** in the R console or the Stop button.

---

## API requirements

- **CENSUS_API_KEY** must be set (e.g. in `.Renviron` or system environment) before clicking **Fetch from API**. The app will show a red error if the key is missing.
- API endpoint: `https://api.census.gov/data/timeseries/bds`. Variable list: [Census BDS variables](https://api.census.gov/data/timeseries/bds/variables.html).

---

## Usage instructions

1. **Start the app** (see [How to run](#how-to-run)).
2. In the **sidebar**:
   - Choose a **Metric** (e.g. JOB_CREATION).
   - Choose **Geography**: **US total** or **All states**.
   - Set **Years** with the slider (e.g. 2010–2023).
3. Click **Fetch from API**. Wait for the green success message and row count.
4. View results:
   - **Table** — Paginated table; use the controls below the table to move pages.
   - **Time series** — Line plot of the selected metric over years.
5. Change options and click **Fetch from API** again to load different data.

---

## Screenshots

*Add your screenshots here for submission (e.g. app interface, successful fetch, table view, time series plot, error message when key is missing).*

| Screenshot | Description |
|------------|-------------|
| *(image)*  | App interface (sidebar + main area). |
| *(image)*  | Successful query: green message + Table tab with data. |
| *(image)*  | Time series tab with plot. |
| *(image)*  | *(Optional)* Error when API key is not set. |

---

## Files

| File | Purpose |
|------|---------|
| [`app.R`](app.R) | Main Shiny app (UI and server). |
| [`bds_api.R`](bds_api.R) | Helper: calls Census BDS API and returns tidy data. |
| [`install_deps.R`](install_deps.R) | One-time script to install required R packages. |
| [`DESCRIPTION`](DESCRIPTION) | R package dependency list. |
| [`README.md`](README.md) | This file. |
| `data/` | Optional: CSV from `lab1.R` can be saved here; app fetches live by default. |

---

← [Back to LAB: Build a Shiny App Using Cursor](../LAB_cursor_shiny_app.md)
