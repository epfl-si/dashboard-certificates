library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))
source(here("clean_data.R"))

library(dplyr)

data <- ssl_data
# categories expiration :
# 1 pour < aujourd'hui
# 2 pour < aujourd'hui + 30
# 3 pour < aujourd'hui + 60
# 4 pour < aujourd'hui + 90
# 5 pour >= aujourd'hui + 90

data_due_date <- data %>%
  mutate(cat_exp = case_when(
    validTo < Sys.Date() ~ 1,
    validTo < Sys.Date() + 30 ~ 2,
    validTo < Sys.Date() + 60 ~ 3,
    validTo < Sys.Date() + 90 ~ 4,
    TRUE ~ 5
  ))
