library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))

library(elastic)
library(dplyr)
library(jsonlite)

# open connection with elasticsearch
con_elasticsearch <- elastic::connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema = transport_schema)

page_size <- 100
# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = page_size, raw = TRUE))$hits$hits$"_source"
# import cmdb data from elasticsearch
scroll_time <- "1m"
initial_search <- Search(con_elasticsearch, index = "cmdb", size = page_size, scroll = scroll_time, raw = TRUE)
data <- fromJSON(initial_search)$hits$hits
scroll_id <- scroll(con_elasticsearch, initial_search)$`_scroll_id`
cmdb_data <- fromJSON(initial_search)$hits$hits$"_source"

while (length(data) > 0) {
    scroll_response <- scroll(con_elasticsearch, scroll_id = scroll_id, scroll = scroll_time)
    data <- fromJSON(scroll_response)$hits$hits
    data_temp <- fromJSON(scroll_response)$hits$hits$"_source"
    cmdb_data <- rbind(cmdb_data, data_temp)
    scroll_id <- scroll(con_elasticsearch, scroll_response)$`_scroll_id`
}

# filter ssl data if LAMP
# FIXME : liste correcte et exhaustive ?
ssl_data <- ssl_data %>% filter(!str_detect(ipv4, "^127\\.178\\.226\\..*"), !str_detect(ipv4, "^127\\.178\\.222\\..*"), !str_detect(ipv4, "^127\\.178\\.32\\..*"))

# filter ssl data if wildcards
ssl_data <- ssl_data %>% filter(!str_detect(subject$CN, "\\*"), !str_detect(as.character(san), "\\*"))

# filter ssl data if ips not in cmdb data
ssl_data <- ssl_data %>% filter(ipv4 %in% cmdb_data$ip)

# filter cmdb data if ips not in ssl data
cmdb_data <- cmdb_data %>% filter(ip %in% ssl_data$ipv4)

# clean data types and column names
ssl_data <- ssl_data %>% mutate(ipv4 = as.character(ipv4), san = sapply(san, paste, collapse = ", "), ciphers = sapply(ciphers, paste, collapse = ", "), technologies = sapply(technologies, paste, collapse = ", "), validFrom = as.Date(validFrom), validTo = as.Date(validTo)) %>% dplyr::rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)
