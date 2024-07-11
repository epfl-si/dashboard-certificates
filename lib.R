# packages install
packages <- c("DBI", "dotenv", "dplyr", "DT", "elastic", "here", "httr", "jsonlite", "roperators", "RSQLite", "shiny", "shinydashboard")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p)
  }
}
