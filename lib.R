# Liste des packages nécessaires
# FIXME : besoin de "Cairo" ?
packages <- c("DBI", "dotenv", "plyr", "dplyr", "DT", "elastic", "here", "httr", "jsonlite", 
              "kableExtra", "knitr", "log4r", "roperators", "RSQLite", "shiny", "shinydashboard", 
              "shiny.fluent", "stringr", "tidyr", "ragg", "ggplot2")

# Installation des packages manquants
for (p in packages) {
  if (!(p %in% rownames(installed.packages()))) {
    message("Installing package: ", p)
    tryCatch({
      install.packages(p, dependencies = TRUE, INSTALL_opts = '--no-lock')
    }, error = function(e) {
      message("Error installing package ", p, ": ", e$message)
    })
  } else {
    message("Package already installed: ", p)
  }
}
