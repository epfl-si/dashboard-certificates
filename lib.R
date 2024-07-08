# packages install
packages <- c("DBI", "dotenv", "dplyr", "elastic", "here", "httr", "jsonlite", "RSQLite")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p)
  }
}
