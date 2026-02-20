FROM rocker/r-ver:4.3.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages(c('shiny','bslib','DT','httr','jsonlite','dplyr','purrr','readr','tidyr','ggplot2'), repos='https://cloud.r-project.org')"

WORKDIR /app
COPY . /app

EXPOSE 8080

CMD ["R", "-e", "shiny::runApp('/app', host='0.0.0.0', port=as.integer(Sys.getenv('PORT', '8080')))"]
