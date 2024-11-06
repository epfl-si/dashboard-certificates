#source("lib.R")

# FIXME : utilisation de env. avec credentials
# load env. variables
#library(dotenv)
#load_dot_env()

db_path <- "/srv/cert_dashboard/cmdb.sqlite"
host_elasticsearch <- "elasticsearch"
port_elasticsearch <- 9200
user_elasticsearch <- "elastic"
password_elasticsearch <- "secret"
shiny_host <- "0.0.0.0"
