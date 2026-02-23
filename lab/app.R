# AI-Powered Reporter Software (SYSEN 5381 Lab)
# How to run:
#   shiny::runApp("lab")
# API key setup:
#   Census (optional but recommended): Sys.setenv(CENSUS_API_KEY = "...")
#   OR put in .Renviron file in project root or home directory
# AI setup:
#   OpenAI: Sys.setenv(OPENAI_API_KEY = "...", OPENAI_MODEL = "gpt-4o-mini")
#   OR Ollama: Sys.setenv(OLLAMA_MODEL = "smollm2:1.7b", OLLAMA_HOST = "http://localhost:11434")

# Load environment variables from .Renviron and .env files
# Try multiple locations in order of preference
renv_paths = c(
  ".Renviron",                    # Current directory (lab/)
  "../dsai/.Renviron",            # Parent dsai directory
  "../../dsai/.Renviron",          # Two levels up
  "~/.Renviron"                   # Home directory
)
for (path in renv_paths) {
  if (file.exists(path)) {
    readRenviron(path)
    break
  }
}

# Also try to load from .env files (for Python-style projects)
env_paths = c(
  "../dsai/.env",                 # Parent dsai directory
  "../../dsai/.env",              # Two levels up
  ".env"                          # Current directory
)
for (path in env_paths) {
  if (file.exists(path)) {
    env_lines = readLines(path, warn = FALSE)
    for (line in env_lines) {
      line = trimws(line)
      if (nchar(line) > 0 && !startsWith(line, "#") && grepl("=", line)) {
        parts = strsplit(line, "=", fixed = TRUE)[[1]]
        if (length(parts) == 2) {
          key = trimws(parts[1])
          value = trimws(parts[2])
          # Only set if not already set
          if (!nzchar(Sys.getenv(key))) {
            do.call(Sys.setenv, setNames(list(value), key))
          }
        }
      }
    }
    break
  }
}

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(lubridate)
  library(glue)
})

source("mrts_helpers.R")

month_opts = month_choices("2018-01", "2025-12")

ui = fluidPage(
  theme = bs_theme(bootswatch = "flatly"),
  titlePanel("AI-Powered MRTS Reporter"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Query Controls"),
      radioButtons(
        "industry_mode",
        "Industry selection mode",
        choices = c("Single-select" = "single", "Multi-select" = "multi"),
        selected = "multi"
      ),
      uiOutput("industry_selector_ui"),
      actionButton("confirm_industries", "Confirm Selected Industry(ies)", class = "btn-warning"),
      uiOutput("industry_confirm_status"),
      selectInput("start_month", "Start month (YYYY-MM)", choices = month_opts, selected = "2020-01"),
      selectInput("end_month", "End month (YYYY-MM)", choices = month_opts, selected = tail(month_opts, 1)),
      selectInput("data_type", "Data type", choices = MRTS_DATA_TYPES, selected = "default"),
      checkboxInput("show_growth", "Show derived series (YoY% / MoM%)", value = FALSE),
      radioButtons(
        "growth_type",
        "Derived series type",
        choices = c("YoY %" = "yoy", "MoM %" = "mom"),
        selected = "yoy"
      ),
      actionButton("run_query", "Run Query", class = "btn-primary"),
      actionButton("generate_ai_report", "Generate AI Report", class = "btn-success"),
      downloadButton("download_report", "Download Report"),
      hr(),
      uiOutput("sidebar_status")
    ),
    mainPanel(
      width = 9,
      tabsetPanel(
        tabPanel(
          "Data",
          br(),
          uiOutput("data_message"),
          DTOutput("data_table")
        ),
        tabPanel(
          "Trends",
          br(),
          uiOutput("trends_message"),
          plotOutput("trends_plot", height = "450px")
        ),
        tabPanel(
          "AI Report",
          br(),
          uiOutput("ai_status"),
          tags$h4("Metadata"),
          tableOutput("ai_metadata"),
          tags$h4("Generated Report"),
          verbatimTextOutput("ai_report_text")
        )
      )
    )
  )
)

server = function(input, output, session) {
  data_state = reactiveVal(NULL)
  data_error = reactiveVal(NULL)
  ai_state = reactiveVal(NULL)
  ai_error = reactiveVal(NULL)
  ai_generated_at = reactiveVal(NULL)
  confirmed_industries = reactiveVal(character(0))

  output$industry_selector_ui = renderUI({
    if (identical(input$industry_mode, "single")) {
      selectInput(
        "industries_single",
        "Industry (NAICS/category)",
        choices = MRTS_INDUSTRIES,
        selected = unname(MRTS_INDUSTRIES)[1],
        multiple = FALSE
      )
    } else {
      fluidRow(
        column(
          width = 6,
          selectizeInput(
            "industries_multi_pick",
            "Pick candidate industries",
            choices = MRTS_INDUSTRIES,
            selected = unname(MRTS_INDUSTRIES)[1:2],
            multiple = TRUE,
            options = list(placeholder = "Search industries")
          )
        ),
        column(
          width = 6,
          checkboxGroupInput(
            "industries_multi_checked",
            "Apply (check exactly 2)",
            choices = MRTS_INDUSTRIES,
            selected = unname(MRTS_INDUSTRIES)[1:2]
          )
        )
      )
    }
  })

  selected_industries = reactive({
    if (identical(input$industry_mode, "single")) {
      if (is.null(input$industries_single) || !nzchar(input$industries_single)) return(character(0))
      return(input$industries_single)
    }
    checked = input$industries_multi_checked %||% character(0)
    picked = input$industries_multi_pick %||% character(0)
    if (length(checked) > 0) return(checked)
    picked
  })

  labels_from_codes = function(codes) {
    labels = names(MRTS_INDUSTRIES)[match(codes, unname(MRTS_INDUSTRIES))]
    ifelse(is.na(labels), codes, labels)
  }

  selected_industry_labels = reactive({
    labels_from_codes(selected_industries())
  })

  confirmed_industry_labels = reactive({
    labels_from_codes(confirmed_industries())
  })

  output$industry_confirm_status = renderUI({
    confirmed = confirmed_industries()
    if (length(confirmed) == 0) {
      return(tags$p("No confirmed industries yet.", class = "text-warning"))
    }
    tags$p(glue("Confirmed: {paste(confirmed_industry_labels(), collapse = ', ')}"), class = "text-success")
  })

  observeEvent(input$confirm_industries, {
    raw_selected = selected_industries()

    if (identical(input$industry_mode, "multi") && length(raw_selected) != 2) {
      showNotification("Please select exactly 2 industries in Multi-select mode, then click confirm.", type = "error")
      return()
    }
    if (identical(input$industry_mode, "single") && length(raw_selected) != 1) {
      showNotification("Please select 1 industry in Single-select mode, then click confirm.", type = "error")
      return()
    }
    if (input$start_month > input$end_month) {
      showNotification("Start month must be <= end month before confirming.", type = "error")
      return()
    }

    probe_params = list(
      industries = raw_selected,
      start_month = input$start_month,
      end_month = input$start_month,
      data_type = input$data_type
    )

    probe = withProgress(message = "Checking API with selected industry(ies)...", value = 0, {
      incProgress(0.3, detail = "Running probe")
      res = tryCatch(fetch_mrts_data(probe_params), error = function(e) e)
      incProgress(1, detail = "Done")
      res
    })

    if (inherits(probe, "error")) {
      showNotification(glue("API check failed: {conditionMessage(probe)}"), type = "error", duration = 8)
      return()
    }

    confirmed_industries(raw_selected)
    showNotification(glue("Confirmed {length(raw_selected)} industry(ies). API probe passed."), type = "message", duration = 6)
  }, ignoreInit = TRUE)

  observeEvent(input$run_query, {
    ai_state(NULL)
    ai_error(NULL)
    ai_generated_at(NULL)
    data_error(NULL)

    industries = confirmed_industries()
    if (length(industries) == 0) {
      msg = "No confirmed industries. Select industry(ies), click 'Confirm Selected Industry(ies)', then Run Query."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "error")
      return()
    }
    if (!setequal(selected_industries(), industries)) {
      msg = "Industry selection changed after confirmation. Please click 'Confirm Selected Industry(ies)' again."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "warning")
      return()
    }

    if (input$start_month > input$end_month) {
      msg = "Start month is after end month. Please fix the date range."
      data_state(NULL)
      data_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    query_params = list(
      industries = industries,
      start_month = input$start_month,
      end_month = input$end_month,
      data_type = input$data_type
    )

    out = withProgress(message = "Running MRTS query...", value = 0, {
      incProgress(0.2, detail = "Sending request")
      result = tryCatch(
        fetch_mrts_data(query_params),
        error = function(e) e
      )
      incProgress(1, detail = "Done")
      result
    })

    if (inherits(out, "error")) {
      msg = conditionMessage(out)
      data_state(NULL)
      data_error(msg)
      showNotification(glue("API query failed: {msg}"), type = "error")
      return()
    }

    if (nrow(out) == 0) {
      msg = "API returned empty data for your selection."
      data_state(out)
      data_error(msg)
      showNotification(msg, type = "warning")
      return()
    }

    # Check for date range warning and notify user
    date_warning = attr(out, "date_range_warning")
    if (!is.null(date_warning)) {
      showNotification(date_warning, type = "warning", duration = 10)
    }

    data_state(out)
    data_error(NULL)
    showNotification(glue("Query complete: {nrow(out)} rows loaded."), type = "message")
  }, ignoreInit = TRUE)

  output$sidebar_status = renderUI({
    data = data_state()
    key_set = nzchar(Sys.getenv("CENSUS_API_KEY"))
    tags$div(
      p(if (key_set) "CENSUS_API_KEY: set" else "CENSUS_API_KEY: not set", class = if (key_set) "text-success" else "text-danger"),
      p(
        if (length(confirmed_industries()) == 0) "Industry confirm: pending"
        else glue("Industry confirm: {paste(confirmed_industry_labels(), collapse = ', ')}"),
        class = if (length(confirmed_industries()) == 0) "text-warning" else "text-success"
      ),
      p(if (is.null(data)) "No query run yet." else glue("Current rows: {nrow(data)}"), class = "text-muted")
    )
  })

  output$data_message = renderUI({
    err = data_error()
    data = data_state()
    if (!is.null(err)) {
      return(div(class = "alert alert-warning", strong("Notice: "), err))
    }
    if (is.null(data)) {
      return(div(class = "alert alert-info", "Click 'Run Query' to fetch MRTS data."))
    }
    div(class = "alert alert-success", glue("Rows returned: {nrow(data)}"))
  })

  output$data_table = renderDT({
    data = data_state()
    
    # Check if data exists
    if (is.null(data)) {
      return(datatable(
        data.frame(Message = "Run Query to load data.", stringsAsFactors = FALSE),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      ))
    }
    
    if (nrow(data) == 0) {
      return(datatable(
        data.frame(Message = "No data to display for this selection.", stringsAsFactors = FALSE),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      ))
    }

    # Convert to data.frame and handle different column types
    tryCatch({
      safe_df = as.data.frame(data, stringsAsFactors = FALSE)
      
      # Convert Date columns to character
      for (col_name in names(safe_df)) {
        if (inherits(safe_df[[col_name]], "Date")) {
          safe_df[[col_name]] = format(safe_df[[col_name]], "%Y-%m-%d")
        } else if (is.list(safe_df[[col_name]])) {
          safe_df[[col_name]] = vapply(safe_df[[col_name]], function(x) {
            paste(as.character(unlist(x)), collapse = ", ")
          }, character(1))
        } else if (!is.numeric(safe_df[[col_name]]) && !is.character(safe_df[[col_name]])) {
          safe_df[[col_name]] = as.character(safe_df[[col_name]])
        }
      }
      
      # Ensure all columns are valid for DT
      safe_df = safe_df[, sapply(safe_df, function(x) !all(is.na(x))), drop = FALSE]
      
      if (ncol(safe_df) == 0) {
        return(datatable(
          data.frame(Message = "No valid columns to display.", stringsAsFactors = FALSE),
          options = list(dom = "t", pageLength = 1),
          rownames = FALSE
        ))
      }

      safe_df[] = lapply(safe_df, as.character)
      names(safe_df) = make.names(names(safe_df), unique = TRUE)

      datatable(
        safe_df,
        options = list(
          pageLength = 15,
          scrollX = TRUE,
          dom = "ftip"
        ),
        rownames = FALSE
      )
    }, error = function(e) {
      datatable(
        data.frame(
          Error = paste("Table render error:", conditionMessage(e)),
          stringsAsFactors = FALSE
        ),
        options = list(dom = "t", pageLength = 1),
        rownames = FALSE
      )
    })
  }, server = FALSE)

  trend_df = reactive({
    df = data_state()
    
    if (is.null(df)) {
      return(data.frame())
    }
    
    if (nrow(df) == 0) {
      return(data.frame())
    }
    
    # Ensure required columns exist
    required_cols = c("month", "value", "industry")
    missing_cols = setdiff(required_cols, names(df))
    if (length(missing_cols) > 0) {
      return(data.frame())
    }

    tryCatch({
      # Determine primary data_type: use selected one, or "SM" if "default"
      primary_dtype = if (input$data_type == "default") "SM" else input$data_type
      
      # Filter to primary data_type only to avoid mixing multiple series
      df_filtered = df %>%
        mutate(
          month = if (inherits(month, "Date")) month else as.Date(month),
          value = suppressWarnings(as.numeric(value)),
          industry = as.character(industry)
        ) %>%
        filter(!is.na(month), !is.na(value), !is.na(industry), nzchar(industry))
      
      # If data_type column exists, filter to primary sequence
      if ("data_type" %in% names(df_filtered)) {
        df_filtered = df_filtered %>%
          filter(data_type == primary_dtype)
      }
      
      # Aggregate to one point per industry-month, then calculate derived metrics
      df_filtered %>%
        group_by(industry, month) %>%
        summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
        arrange(industry, month) %>%
        group_by(industry) %>%
        mutate(
          # Safe YoY calculation: avoid division by zero and clamp extreme values
          yoy = if_else(
            is.na(lag(value, 12)) | abs(lag(value, 12)) < 1e-6,
            NA_real_,
            pmax(-1000, pmin(10000, 100 * (value / lag(value, 12) - 1)))
          ),
          # Safe MoM calculation: avoid division by zero and clamp extreme values
          mom = if_else(
            is.na(lag(value, 1)) | abs(lag(value, 1)) < 1e-6,
            NA_real_,
            pmax(-1000, pmin(10000, 100 * (value / lag(value, 1) - 1)))
          )
        ) %>%
        ungroup()
    }, error = function(e) {
      data.frame()
    })
  })

  output$trends_plot = renderPlot({
    df = trend_df()
    
    # Check if data exists
    if (is.null(df) || nrow(df) == 0) {
      plot.new()
      text(0.5, 0.5, "No trend data available. Run Query first.", cex = 1.2)
      return(invisible(NULL))
    }

    # Determine which column to plot
    y_col = if (isTRUE(input$show_growth) && input$growth_type == "yoy") "yoy" else if (isTRUE(input$show_growth)) "mom" else "value"
    y_label = if (y_col == "yoy") "YoY % change" else if (y_col == "mom") "MoM % change" else "Sales value"
    
    # Ensure the column exists
    if (!y_col %in% names(df)) {
      y_col = "value"
      y_label = "Sales value"
    }

    # Filter and prepare data for plotting
    df_plot = df %>%
      filter(!is.na(month), !is.na(.data[[y_col]]), !is.na(industry), nzchar(industry)) %>%
      arrange(industry, month)

    if (nrow(df_plot) == 0) {
      plot.new()
      text(0.5, 0.5, "No valid data points after filtering.", cex = 1.2)
      return(invisible(NULL))
    }

    tryCatch({
      # Use base plotting here to avoid device/text rendering regressions in some deployments
      wide_df = df_plot %>%
        select(month, industry, y = all_of(y_col)) %>%
        tidyr::pivot_wider(names_from = industry, values_from = y, values_fn = mean) %>%
        arrange(month)

      x = as.Date(wide_df$month)
      y_mat = as.matrix(wide_df[, setdiff(names(wide_df), "month"), drop = FALSE])
      storage.mode(y_mat) = "double"

      if (length(x) == 0 || ncol(y_mat) == 0) {
        plot.new()
        text(0.5, 0.5, "No valid series to plot.")
        return(invisible(NULL))
      }

      yr = range(y_mat, na.rm = TRUE)
      if (!all(is.finite(yr))) {
        plot.new()
        text(0.5, 0.5, "No finite values to plot.")
        return(invisible(NULL))
      }

      cols = grDevices::hcl.colors(max(3, ncol(y_mat)), "Dark 3")[seq_len(ncol(y_mat))]
      plot(
        x, y_mat[, 1],
        type = "l", lwd = 2, col = cols[1],
        xlab = "Month", ylab = y_label, ylim = yr,
        main = "Monthly Retail Trend by Industry"
      )
      if (ncol(y_mat) > 1) {
        for (i in 2:ncol(y_mat)) {
          lines(x, y_mat[, i], col = cols[i], lwd = 2)
        }
      }
      legend("topright", legend = colnames(y_mat), col = cols, lty = 1, lwd = 2, bty = "n", cex = 0.85)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Plot error:", conditionMessage(e)), cex = 1.2)
    })
  })
  
  output$trends_message = renderUI({
    df = data_state()
    if (is.null(df) || nrow(df) == 0) {
      return(div(class = "alert alert-info", "Run Query first to see trends chart."))
    }
    div(class = "alert alert-success", glue("Showing trends for {nrow(df)} data points across {length(unique(df$industry))} industry(ies)."))
  })

  observeEvent(input$generate_ai_report, {
    ai_error(NULL)
    df = data_state()

    if (is.null(df) || nrow(df) == 0) {
      msg = "No query data available. Click Run Query first."
      ai_state(NULL)
      ai_error(msg)
      showNotification(msg, type = "error")
      return()
    }

    # Filter to primary data_type only for AI report (same logic as trend_df)
    primary_dtype = if (input$data_type == "default") "SM" else input$data_type
    df_primary = df
    
    # If data_type column exists, filter to primary sequence only
    if ("data_type" %in% names(df_primary)) {
      df_primary = df_primary %>%
        filter(data_type == primary_dtype)
      
      if (nrow(df_primary) == 0) {
        msg = glue("No data available for data_type '{primary_dtype}'. Try a different data type.")
        ai_state(NULL)
        ai_error(msg)
        showNotification(msg, type = "error")
        return()
      }
    }
    
    # Compute stats only on primary sequence
    stats = compute_summary_stats(df_primary)
    params = list(
      industry_labels = confirmed_industry_labels(),
      start_month = input$start_month,
      end_month = input$end_month,
      data_type = input$data_type,
      primary_data_type = primary_dtype,  # Add this for AI prompt clarity
      endpoint = MRTS_ENDPOINTS[1]
    )

    report = tryCatch(
      generate_ai_report(stats, params),
      error = function(e) e
    )

    if (inherits(report, "error")) {
      msg = conditionMessage(report)
      ai_state(NULL)
      ai_error(msg)
      showNotification(glue("AI generation failed: {msg}"), type = "error")
      return()
    }

    # Safely extract attributes with defaults
    model_attr = attr(report, "model_used")
    backend_attr = attr(report, "backend")
    
    ai_state(list(
      text = as.character(report),
      model = if (is.null(model_attr)) "unknown" else as.character(model_attr),
      backend = if (is.null(backend_attr)) "unknown" else as.character(backend_attr),
      stats = stats,
      params = params
    ))
    ai_generated_at(Sys.time())
    showNotification("AI report generated successfully.", type = "message")
  }, ignoreInit = TRUE)

  output$ai_status = renderUI({
    err = ai_error()
    ai = ai_state()
    if (!is.null(err)) {
      return(div(class = "alert alert-danger", strong("AI Error: "), err))
    }
    if (is.null(ai)) {
      return(div(class = "alert alert-info", "Click 'Generate AI Report' after running a query."))
    }
    div(class = "alert alert-success", "AI report is ready.")
  })

  output$ai_metadata = renderTable({
    ai = ai_state()
    req(ai)
    # Ensure ai is a list and has required fields
    if (!is.list(ai)) {
      return(data.frame(Field = "Error", Value = "Invalid AI state", stringsAsFactors = FALSE))
    }
    # Safely access nested fields with defaults
    industry_labels = if (is.list(ai$params) && !is.null(ai$params$industry_labels)) {
      paste(ai$params$industry_labels, collapse = ", ")
    } else { "N/A" }
    
    start_month = if (is.list(ai$params) && !is.null(ai$params$start_month)) {
      ai$params$start_month
    } else { "N/A" }
    
    end_month = if (is.list(ai$params) && !is.null(ai$params$end_month)) {
      ai$params$end_month
    } else { "N/A" }
    
    total_rows = if (is.list(ai$stats) && !is.null(ai$stats$total_rows)) {
      ai$stats$total_rows
    } else { 0 }
    
    backend = if (!is.null(ai$backend)) ai$backend else "unknown"
    model = if (!is.null(ai$model)) ai$model else "unknown"
    
    endpoint = if (is.list(ai$params) && !is.null(ai$params$endpoint)) {
      ai$params$endpoint
    } else { "N/A" }
    
    data.frame(
      Field = c("Industries selected", "Date range", "Rows", "Generated at", "Model used", "Endpoint"),
      Value = c(
        industry_labels,
        paste(start_month, "to", end_month),
        total_rows,
        as.character(ai_generated_at()),
        paste(backend, "-", model),
        endpoint
      ),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, bordered = TRUE, spacing = "s")

  output$ai_report_text = renderText({
    ai = ai_state()
    if (is.null(ai)) {
      return("No report generated yet.")
    }
    # Ensure ai is a list before accessing with $
    if (!is.list(ai)) {
      return("Error: Invalid AI state format.")
    }
    # Ensure text is always a character string
    txt = if (!is.null(ai$text)) ai$text else ""
    if (is.null(txt)) return("")
    if (!is.character(txt)) txt = as.character(txt)
    txt
  })

  output$download_report = downloadHandler(
    filename = function() {
      paste0("mrts_ai_report_", format(Sys.Date(), "%Y%m%d"), ".md")
    },
    content = function(file) {
      ai = ai_state()
      if (is.null(ai)) {
        showNotification("Generate AI Report before downloading.", type = "error")
        writeLines("No AI report generated yet. Please click 'Generate AI Report' first.", file)
        return()
      }

      # Safely access nested fields
      if (!is.list(ai) || !is.list(ai$stats) || is.null(ai$stats$per_industry)) {
        stats_tbl = data.frame()
      } else {
        stats_tbl = ai$stats$per_industry %>%
          mutate(across(where(is.numeric), ~ round(.x, 2)))
      }

      # Safely extract params with defaults
      industry_labels = if (is.list(ai$params) && !is.null(ai$params$industry_labels)) {
        paste(ai$params$industry_labels, collapse = ", ")
      } else { "N/A" }
      
      start_month = if (is.list(ai$params) && !is.null(ai$params$start_month)) {
        ai$params$start_month
      } else { "N/A" }
      
      end_month = if (is.list(ai$params) && !is.null(ai$params$end_month)) {
        ai$params$end_month
      } else { "N/A" }
      
      data_type = if (is.list(ai$params) && !is.null(ai$params$data_type)) {
        ai$params$data_type
      } else { "N/A" }
      
      endpoint = if (is.list(ai$params) && !is.null(ai$params$endpoint)) {
        ai$params$endpoint
      } else { "N/A" }
      
      backend = if (!is.null(ai$backend)) ai$backend else "unknown"
      model = if (!is.null(ai$model)) ai$model else "unknown"

      header = c(
        "# AI-Powered MRTS Report",
        "",
        glue("- Generated: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}"),
        glue("- Industries: {industry_labels}"),
        glue("- Date range: {start_month} to {end_month}"),
        glue("- Data type: {data_type}"),
        glue("- Endpoint: {endpoint}"),
        glue("- Model: {backend} / {model}"),
        ""
      )

      stats_lines = if (nrow(stats_tbl) > 0) {
        capture.output(print(stats_tbl, row.names = FALSE))
      } else {
        "No statistics available."
      }
      
      report_text = if (!is.null(ai$text) && is.character(ai$text)) {
        ai$text
      } else if (!is.null(ai$text)) {
        as.character(ai$text)
      } else {
        "No report text available."
      }
      
      report_lines = c(
        header,
        "## AI Report",
        "",
        report_text,
        "",
        "## Data Summary (Per-Industry Stats)",
        "",
        "```",
        stats_lines,
        "```"
      )
      writeLines(report_lines, file)
    }
  )
}

shinyApp(ui = ui, server = server)
