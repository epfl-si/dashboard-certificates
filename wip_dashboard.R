library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))
source(here::here("clean_data.R"))

# TODO : supprimer les librairies plus utilisees et mettre a jour fichier lib.R
library(shiny)
library(shinydashboard)
library(shiny.fluent)
library(DT)
library(RSQLite)
library(dplyr)
library(jsonlite)
library(roperators)
library(log4r)
library(tidyr)
library(kableExtra)
library(knitr)
library(ggplot2)
library(plyr)

options(shiny.host = shiny_host)
options(shiny.port = 8180)

# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import ssl data from elasticsearch
ssl_data <- ssl_data %>%
  mutate(ipv4 = as.character(ipv4)) %>%
  mutate(validFrom = as.Date(validFrom), validTo = as.Date(validTo)) %>%
  dplyr::rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)

# clean ssl data (san, hostname, ip, date_debut et date_fin)
ssl_specific <- ssl_data %>%
  select(san, hostname, ip, date_debut, date_fin) %>%
  arrange(hostname)

# table with all ssl data
ssl_all <- ssl_data

# TODO : choisir colonnes dans cmdb et ssl selon selection de Patrick
# selection of columns from ssl to display (sans ip, hostname et san car rajoutes plus tard)
column_default <- c("date_debut", "date_fin")
column_choices <- names(ssl_all)
# FIXME : comment enlever le hostname sans casser la recherche pour pop up avec info du certificat ?
column_choices <- column_choices[column_choices != "ip" & column_choices != "hostname" & column_choices != "san"]

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi, tabName) {
  mi$children[[1]]$attribs["data-toggle"] <- "tab"
  mi$children[[1]]$attribs["data-value"] <- tabName
  mi
}

# title
header <- dashboardHeader(title = "Certificats SSL")

# sidebar (column selection)
sidebar <- dashboardSidebar(
  collapsed = TRUE,
  sidebarMenu(
    convertMenuItem(
      menuItem("Choix des colonnes",
        tabName = "table",
        icon = icon("list"),
        checkboxGroupInput("columns_current", label = NULL, choices = column_choices, selected = column_default)
      ),
      tabName = "table"
    )
  )
)

# body (filters (expired cert and period) + table)
body <- dashboardBody(
  tabItems(
    tabItem(
      tabName = "table",
      fluidPage(
        fluidRow(
          column(
            width = 3,
            box(
              width = NULL,
              h4(strong("Choix des filtres :"), style = "text-align: center;"),
              checkboxInput("expired_filter", "Afficher les certificats échus ?", TRUE),
              hr(style = "border-color: black;"),
              checkboxInput("periode_filter", "Filtrer selon la période ?", FALSE),
              conditionalPanel(
                condition = "input.periode_filter == true", dateRangeInput("date_fin_plage", label = "Période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd")
              )
            )
          ),
          column(
            width = 9,
            h4(strong("Affichage des échéances des certificats :"), style = "text-align: center;"),
            DTOutput("df_all")
          )
        ),
        fluidRow(
          plotOutput("plot")
        )
      )
    )
  )
)

# user interface
ui <- dashboardPage(
  skin = "red",
  header,
  sidebar,
  body
)

# server
server <- function(input, output, session) {

  # function to filter ssl data
  filtered_data <- reactive({
    data_filtred <- ssl_all

    # time
    date_fin_min <- input$date_fin_plage[1]
    date_fin_max <- input$date_fin_plage[2]
    if (!input$expired_filter) {
      data_filtred <- data_filtred %>% filter(date_fin >= Sys.Date())
    }
    if (input$periode_filter && date_fin_min <= date_fin_max) {
      data_filtred <- data_filtred %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
    }

    # choice of columns
    data <- data_filtred[, input$columns_current, drop = FALSE]

    if (nrow(data) > 0) {
      # add column with ip
      data$ip <- data_filtred$ip
      data <- data %>% select(ip, everything())

      # add column with hostname
      data$hostname <- data_filtred$hostname
      data <- data %>% select(hostname, everything())

      # add column with san
      data$san <- data_filtred$san
      data <- data %>% select(san, everything())

      # add column to display pop up with certificate information
      data$info <- '<i class=\"fa fa-info-circle\"></i>'
      data <- data %>% select(info, everything())
    } else {
      data <- NULL
    }
    return(data)
  })

  # main table with data and selected columns
  output$df_all <- renderDT({
    data_used <- filtered_data()
    if (!is.null(data_used)) {
      datatable(data_used, escape = FALSE, selection = "single", options = list(scrollX = TRUE, dom = "frtip", pageLength = 10), class = "stripe hover", rownames = FALSE)
    } else {
      datatable(data.frame(Message = "Aucun certificat ne correspond..."), selection = "single", options = list(dom = "rt", pageLength = 10), class = "stripe hover", rownames = FALSE)
    }
  })

  # pop up when click on column "info" in main table to display cert info
  observeEvent(input$df_all_cell_clicked, {
    if (!is.null(input$df_all_cell_clicked$value)) {
      if (input$df_all_cell_clicked$col == 0) {
        selected_row <- filtered_data()[input$df_all_cell_clicked$row, , drop = FALSE]
        cert_data <- ssl_all[selected_row$ip == ssl_all$ip & selected_row$hostname == ssl_all$hostname, ]

        # subject name
        output$subject_name <- renderTable({
          cert_data$subject %>%
            select(CN) %>%
            rename("Common Name" = CN)
        })

        # issuer name
        output$issuer_name <- renderTable({
          cert_data$issuer %>%
            select(C, O, CN) %>%
            rename("Country" = C, "Organization" = O, "Common Name" = CN)
        })

        # validity
        output$validity <- renderUI({
          cert_data %>%
            select(date_debut, date_fin) %>%
            rename("Not Before" = date_debut, "Not After" = date_fin) %>%
            kable(format = "html", row.names = FALSE) %>%
            kable_styling() %>%
            HTML()
        })

        # subject alt names
        output$subject_alt_names <- renderTable({
          san <- cert_data %>% select(san)
          as.data.frame(lapply(san, function(col) {
            if (is.list(col)) {
              sapply(col, paste, collapse = ", ")
            } else {
              col
            }
          })) %>% rename("DNS Name" = san)
        })

        showModal(modalDialog(title = "Informations du certificat", easyClose = TRUE, "Subject Name", tableOutput("subject_name"), tags$hr(style = "border-top: 1px solid #000;"), "Issuer Name", tableOutput("issuer_name"), tags$hr(style = "border-top: 1px solid #000;"), "Validity", uiOutput("validity"), tags$hr(style = "border-top: 1px solid #000;"), "Subject Alt Names", tableOutput("subject_alt_names"), footer = modalButton("Fermer")))
      }
    }
  })

  output$plot<- renderPlot({
    data_due_date <- ssl_all %>%
    mutate(cat_exp = case_when(
      date_fin < Sys.Date() - 7 ~ "Expirés",
      date_fin < Sys.Date() ~ "Récemment expirés",
      date_fin < Sys.Date() + 30 ~ "0-30 jours",
      date_fin < Sys.Date() + 60 ~ "31-60 jours",
      date_fin < Sys.Date() + 90 ~ "61-90 jours",
      TRUE ~ "> 91 jours"
    ))

    max_count <- data_due_date %>% dplyr::count(cat_exp) %>% summarise(max_count = max(n)) %>% pull(max_count)
    max_count_round <- round_any(max_count, 100, f = ceiling)

    ggplot(data = data_due_date, aes(x = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")), fill = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")))) + 
        geom_hline(yintercept = seq(0, max_count_round, by = 50), linetype = "solid", linewidth = 0.5, color = "lightgrey") + 
        geom_bar(show.legend = FALSE) + 
        scale_fill_manual(values = c("black", "red", "orange", "yellow", "green", "blue")) + 
        labs(
          title = "Echéances des certificats", 
          x = "Jours jusqu'à échéance", 
          y = "Certificats"
        ) + 
        theme(
          plot.title = element_text(hjust = 0.5, size = 20, margin = margin(b = 10)),
          axis.title.x = element_text(size = 16, margin = margin(t = 20)),
          axis.text.x = element_text(size = 16, margin = margin(t = 0)),
          axis.title.y = element_text(size = 16, margin = margin(r = 20)),
          axis.text.y = element_text(size = 16, margin = margin(r = 5)),
          panel.grid.major = element_blank(),
          panel.grid.minor = element_blank(),
          panel.background = element_blank()
        ) + 
        geom_text(stat = 'count', aes(label = after_stat(count)), vjust = -0.5, size = 6) + 
        scale_y_continuous(limits = c(0, max_count_round), breaks = seq(0, max_count_round, by = 50))
  })
}

shinyApp(ui, server)
