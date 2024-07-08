source("lib.R")

# load env. variables
library(dotenv)
load_dot_env()

db_path <- "/srv/cert_dashboard/R/cmdb.sqlite"
host_elasticsearch <- "elasticsearch"
port_elasticsearch <- 9200
user_elasticsearch <- Sys.getenv("ELASTICSEARCH_USER")
password_elasticsearch <- Sys.getenv("ELASTICSEARCH_PASSWORD")
