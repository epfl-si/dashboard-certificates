source("lib.R")

# load env. variables
library(dotenv)

db_path <- "./volumes/sqlite/cmdb.sqlite"
host_elasticsearch <- "localhost"
port_elasticsearch <- 9200
user_elasticsearch <- Sys.getenv("ELASTICSEARCH_USER")
password_elasticsearch <- Sys.getenv("ELASTICSEARCH_PASSWORD")
shiny_host <- "0.0.0.0"
