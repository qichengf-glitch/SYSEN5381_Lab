#' @name app.R
#' @title Shiny app: Census BDS (Business Dynamics Statistics) Explorer
#' @description
#' Runs the Census BDS API query on user request; supports metric, geography,
#' and year range. Displays results in a table and time series plot.

# 0. SETUP ###################################

## 0.1 Load packages #################################

library(shiny)
library(bslib)
library(DT)
library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(readr)
library(tidyr)
library(ggplot2)

## 0.2 Source helper ####################################

# Resolve bds_api.R robustly for local runs and container runs.
bds_candidates = c(
  "bds_api.R",
  file.path(getwd(), "bds_api.R"),
  "02_productivity/shiny_app/bds_api.R"
)
bds_path = bds_candidates[file.exists(bds_candidates)][1]
if (is.na(bds_path)) {
  stop("Could not find bds_api.R. Checked: ", paste(bds_candidates, collapse = ", "))
}
source(bds_path)

# 1. UI ###################################

ui = fluidPage(
  theme = bslib::bs_theme(
    bootswatch = "flatly",
    base_font = bslib::font_collection("system-ui", "Segoe UI", "Helvetica", "Arial", "sans-serif"),
    heading_font = bslib::font_collection("system-ui", "Segoe UI", "Helvetica", "Arial", "sans-serif")
  ),
  titlePanel("Census BDS: Business Dynamics Statistics"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      p("Query the Census BDS API. Set options and click Fetch.", class = "text-muted"),
      selectInput(
        "metric",
        "Metric",
        choices = c(
          "JOB_CREATION" = "JOB_CREATION",
          "JOB_DESTRUCTION" = "JOB_DESTRUCTION",
          "NET_JOB_CREATION" = "NET_JOB_CREATION",
          "ESTABLISHMENTS_BIRTHS" = "ESTABLISHMENTS_BIRTHS",
          "ESTABLISHMENTS_DEATHS" = "ESTABLISHMENTS_DEATHS"
        ),
        selected = "JOB_CREATION"
      ),
      radioButtons(
        "geography",
        "Geography",
        choices = c(
          "US total" = "us:1",
          "All states" = "state:*"
        ),
        selected = "us:1"
      ),
      sliderInput(
        "year_range",
        "Years",
        min = 1978,
        max = 2023,
        value = c(2010, 2023),
        step = 1,
        sep = ""
      ),
      actionButton("fetch", "Fetch from API", class = "btn-primary"),
      hr(),
      uiOutput("key_status_ui"),
      p(
        "Set CENSUS_API_KEY in .Renviron or system environment if needed.",
        class = "text-muted",
        style = "font-size: 0.85em;"
      )
    ),
    mainPanel(
      width = 9,
      uiOutput("status_ui"),
      br(),
      tabsetPanel(
        tabPanel("Table", DT::dataTableOutput("table")),
        tabPanel("Time series", plotOutput("plot", height = "400px"))
      )
    )
  )
)

# 2. SERVER ###################################

server = function(input, output, session) {

  # Reactive value to hold the fetched data (or error message).
  data_result = reactiveVal(NULL)

  output$key_status_ui = renderUI({
    key_set = nzchar(trimws(Sys.getenv("CENSUS_API_KEY")))
    if (key_set) {
      div(class = "text-success", style = "font-size: 0.9em;", strong("API key: set"))
    } else {
      div(class = "text-danger", style = "font-size: 0.9em;", strong("API key: not set"))
    }
  })

  observeEvent(input$fetch, {
    api_key = Sys.getenv("CENSUS_API_KEY")
    years = seq(input$year_range[1], input$year_range[2], by = 1)

    result = tryCatch(
      {
        df = fetch_bds(
          metric = input$metric,
          geo_for = input$geography,
          years = years,
          api_key = api_key
        )
        list(ok = TRUE, data = df)
      },
      error = function(e) {
        list(ok = FALSE, message = conditionMessage(e))
      }
    )

    data_result(result)
  })

  output$status_ui = renderUI({
    res = data_result()
    if (is.null(res)) {
      return(p("Click \"Fetch from API\" to load data.", class = "text-muted"))
    }
    if (!res$ok) {
      return(
        div(
          class = "alert alert-danger",
          strong("Error: "),
          res$message
        )
      )
    }
    n = nrow(res$data)
    div(
      class = "alert alert-success",
      strong("Success. "),
      sprintf("Fetched %d row(s).", n)
    )
  })

  output$table = DT::renderDataTable({
    res = data_result()
    if (is.null(res) || !res$ok) return(NULL)
    DT::datatable(
      res$data,
      options = list(pageLength = 15, scrollX = TRUE),
      rownames = FALSE
    )
  })

  output$plot = renderPlot({
    res = data_result()
    if (is.null(res) || !res$ok) return(NULL)
    df = res$data
    metric = input$metric

    # If state-level, aggregate by YEAR for the plot.
    if ("state" %in% names(df)) {
      df_plot = df %>%
        group_by(YEAR) %>%
        summarise(!!sym(metric) := sum(.data[[metric]], na.rm = TRUE), .groups = "drop")
    } else {
      df_plot = df
    }

    if (nrow(df_plot) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5, label = "No data to plot", size = 5) +
          theme_void()
      )
    }

    p = ggplot(df_plot, aes(x = YEAR, y = .data[[metric]])) +
      geom_point(size = 2.5, color = "#2c3e50")
    if (nrow(df_plot) >= 2) {
      p = p + geom_line(linewidth = 1.2, color = "#2c3e50")
    }
    p +
      scale_x_continuous(breaks = seq(min(df_plot$YEAR), max(df_plot$YEAR), by = max(1, (max(df_plot$YEAR) - min(df_plot$YEAR)) %/% 10))) +
      labs(title = paste("BDS:", metric), x = "Year", y = metric) +
      theme_minimal(base_size = 14) +
      theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank())
  })
}

# 3. RUN ###################################

shinyApp(ui = ui, server = server)
