library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))

library(elastic)
library(plyr)
library(dplyr)
library(jsonlite)
library(stringr)

# open connection with elasticsearch
con_elasticsearch <- elastic::connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema = transport_schema)

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>%
    mutate(
        ip = as.character(ipv4),
        san = sapply(san, paste, collapse = ", "),
        ciphers = sapply(ciphers, paste, collapse = ", "),
        technologies = sapply(technologies, paste, collapse = ", "),
        date_debut = as.Date(validFrom),
        date_fin = as.Date(validTo),
        CN = purrr::map(subject, function(s) { s$CN })) %>%
    # filter ssl data if LAMP
    # FIXME : liste correcte et exhaustive ?
    filter(!str_detect(ip, "^127\\.178\\.226\\..*"), !str_detect(ip, "^127\\.178\\.222\\..*"), !str_detect(ip, "^127\\.178\\.32\\..*")) %>%
    # filter ssl data if wildcards
    filter(!purrr::map_lgl(CN, ~ any(str_detect(.x, fixed("*")))), !str_detect(as.character(san), fixed("*")))

# import cmdb data from elasticsearch
# OLD
#ssl_ips <- ssl_data$ip %>% unique()
#query <- list(query = list(terms = list(ip = ssl_ips)))
#cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", body = query, size = 10, raw = TRUE))$hits$hits$"_source"
# NEW
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"

# filter ssl data if ips not in cmdb data
ssl_data <- ssl_data %>% filter(ip %in% cmdb_data$ip)

# filter ssl data if self signed certificate
ssl_data <- ssl_data %>% filter(date_fin - date_debut <= 397 & chainOfTrust == 1 & verifiableCert == 1)

# filter cmdb data if ips not in ssl data
cmdb_data <- cmdb_data %>% filter(ip %in% ssl_data$ip)
