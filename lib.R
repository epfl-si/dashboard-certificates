# packages install
packages <- c("DBI", "dotenv", "dplyr", "DT", "elastic", "here", "httr", "jsonlite", "kableExtra", "knitr", "log4r", "roperators", "RSQLite", "shiny", "shinydashboard", "shiny.fluent", "stringr", "tidyr")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p)
  }
}
