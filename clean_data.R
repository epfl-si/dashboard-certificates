library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(elastic)
library(dplyr)
library(jsonlite)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema = "http")

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source"

# import cmdb data from elasticsearch
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"

# filter ssl data if LAMP
# FIXME : liste correcte et exhaustive ?
ssl_data <- ssl_data %>% filter(!str_detect(ipv4, "^127\\.178\\.226\\..*"), !str_detect(ipv4, "^127\\.178\\.222\\..*"), !str_detect(ipv4, "^127\\.178\\.32\\..*"))

# filter ssl data if wildcards
ssl_data <- ssl_data %>% filter(!str_detect(subject$CN, "\\*"), !str_detect(as.character(san), "\\*"))

# filter ssl data if ips not in cmdb data
ssl_data <- ssl_data %>% filter(ipv4 %in% cmdb_data$ip)

# filter cmdb data if ips not in ssl data
cmdb_data <- cmdb_data %>% filter(ip %in% ssl_data$ipv4)
