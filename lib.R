# packages install
packages <- c("Cairo", "DBI", "dotenv", "dplyr", "DT", "elastic", "plyr", "here", "httr", "jsonlite", "kableExtra", "knitr", "log4r", "roperators", "RSQLite", "shiny", "shinydashboard", "shiny.fluent", "stringr", "tidyr", "ragg")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p, dependencies = TRUE, INSTALL_opts = '--no-lock')
  }
}
