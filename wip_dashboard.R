library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))
source(here::here("clean_data.R"))

library(shiny)
library(shinydashboard)
library(shiny.fluent)
library(DT)
library(RSQLite)
library(ggplot2)

options(shiny.host = shiny_host)
options(shiny.port = 8180)

# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# ssl with all columns
ssl_all <- ssl_data

# ssl with due date
ssl_due_date <- ssl_all %>%
  mutate(cat_exp = case_when(
    date_fin < Sys.Date() - 7 ~ "Expirés",
    date_fin < Sys.Date() ~ "Récemment expirés",
    date_fin < Sys.Date() + 30 ~ "0-30 jours",
    date_fin < Sys.Date() + 60 ~ "31-60 jours",
    date_fin < Sys.Date() + 90 ~ "61-90 jours",
    TRUE ~ "> 91 jours"
  ))

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi, tabName) {
  mi$children[[1]]$attribs["data-toggle"] <- "tab"
  mi$children[[1]]$attribs["data-value"] <- tabName
  mi
}

# title
header <- dashboardHeader(title = "Certificats SSL")

# filters
sidebar <- dashboardSidebar(
  collapsed = TRUE,
  sidebarMenu(
    convertMenuItem(
      menuItem("Filtres",
        tabName = "table",
        icon = icon("list"),
        checkboxInput("category_filter", "Filtrer selon la catégorie ?", value = FALSE),
        conditionalPanel(
          condition = "input.category_filter == true",
          checkboxInput("expired", "Expirés", value = FALSE),
          checkboxInput("recently_expired", "Récemment expirés", value = FALSE),
          checkboxInput("expired_before_30_days", "0-30 jours", value = FALSE),
          checkboxInput("expired_before_60_days", "31-60 jours", value = FALSE),
          checkboxInput("expired_before_90_days", "61-90 jours", value = FALSE),
          checkboxInput("expired_after_90_days", "> 91 jours", value = FALSE)
        ),
        hr(style = "border-color: black;"),
        checkboxInput("period_filter", "Filtrer selon la période ?", value = FALSE),
        conditionalPanel(
          condition = "input.period_filter == true", dateRangeInput("date_fin_plage", label = "Période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd")
        ),
        hr(style = "border-color: black;")
      ),
      tabName = "table"
    )
  )
)

# body (plot + table)
body <- dashboardBody(
  tabItem(
    tabName = "table",
    fluidPage(
      fluidRow(
        plotOutput("plot")
      ),
      fluidRow(hr(style = "border-color: black;")),
      fluidRow(
        h4(strong("Détails des certificats"), style = "text-align: center;"),
        div(style = "text-align: center; margin-top: 20px; margin-bottom: 10px;", downloadButton("download_data", "Téléchargement des données", style = "align: left;")),
        div(style = "text-align: center;", actionButton(inputId = "update_cert", label = "Renouveller un certificat", icon = icon("repeat"), onclick = "window.open('https://rauth.epfl.ch/', '_blank')")),
        DTOutput("df")
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

  observe({
    updateCheckboxInput(session, "category_filter", value = FALSE)
    updateCheckboxInput(session, "period_filter", value = FALSE)
    updateDateRangeInput(session, "date_fin_plage", start = Sys.Date(), end = Sys.Date())
    updateCheckboxInput(session, "expired", value = FALSE)
    updateCheckboxInput(session, "recently_expired", value = FALSE)
    updateCheckboxInput(session, "expired_before_30_days", value = FALSE)
    updateCheckboxInput(session, "expired_before_60_days", value = FALSE)
    updateCheckboxInput(session, "expired_before_90_days", value = FALSE)
    updateCheckboxInput(session, "expired_after_90_days", value = FALSE)
  })

  # update checkbox depending on other checkbox
  observeEvent(input$category_filter, {
    if (input$category_filter) {
      updateCheckboxInput(session, "period_filter", value = FALSE)
      updateDateRangeInput(session, "date_fin_plage", start = Sys.Date(), end = Sys.Date())
    }
  })
  observeEvent(input$period_filter, {
    if (input$period_filter) {
      updateCheckboxInput(session, "category_filter", value = FALSE)
      updateCheckboxInput(session, "expired", "Expirés", value = FALSE)
      updateCheckboxInput(session, "recently_expired", value = FALSE)
      updateCheckboxInput(session, "expired_before_30_days", value = FALSE)
      updateCheckboxInput(session, "expired_before_60_days", value = FALSE)
      updateCheckboxInput(session, "expired_before_90_days", value = FALSE)
      updateCheckboxInput(session, "expired_after_90_days", value = FALSE)
    }
  })

  # function to filter ssl data
  filtered_data <- reactive({
    data <- ssl_due_date
    if (input$category_filter) {
      is_filtered <- FALSE
      categories <- c()
      if (input$expired) categories <- c(categories, "Expirés")
      if (input$recently_expired) categories <- c(categories, "Récemment expirés")
      if (input$expired_before_30_days) categories <- c(categories, "0-30 jours")
      if (input$expired_before_60_days) categories <- c(categories, "31-60 jours")
      if (input$expired_before_90_days) categories <- c(categories, "61-90 jours")
      if (input$expired_after_90_days) categories <- c(categories, "> 91 jours")
      data <- data %>% dplyr::filter(cat_exp %in% categories)
    } else if (input$period_filter) {
      date_fin_min <- input$date_fin_plage[1]
      date_fin_max <- input$date_fin_plage[2]
      if (date_fin_min <= date_fin_max) {
        data <- data %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
      } else {
        data <- data.frame(Message = "Dates sélectionnées invalides !")
      }
    }
    if ("date_fin" %in% colnames(data) && nrow(data) > 0) {
      # add column to display pop up with certificate information
      data <- data %>% mutate(info = '<i class=\"fa fa-info-circle\"></i>')
    } else if (nrow(data) == 0) {
      data <- data.frame(Message = "Aucun certificat ne correspond...")
    }
    return(data)
  })

  # plot depending on due date
  output$plot <- renderPlot({
    max_count <- ssl_due_date %>%
      dplyr::count(cat_exp) %>%
      summarise(max_count = max(n)) %>%
      pull(max_count)
    max_count_round <- round_any(max_count, 100, f = ceiling)
    max_count_round_with_margin <- max_count_round + 100

    ggplot(data = ssl_due_date, aes(x = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")), fill = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")))) +
      geom_hline(yintercept = seq(0, max_count_round, by = 50), linetype = "solid", linewidth = 0.5, color = "lightgrey") +
      geom_bar(show.legend = FALSE) +
      scale_fill_manual(values = c("black", "red", "orange", "yellow", "green", "blue")) +
      labs(
        title = "Echéances des certificats",
        x = "",
        y = ""
      ) +
      theme(
        plot.title = element_text(hjust = 0.5, size = 20, margin = margin(b = 7)),
        axis.title.x = element_text(size = 16, margin = margin(t = 20)),
        axis.text.x = element_text(size = 16, margin = margin(t = 0)),
        axis.title.y = element_text(size = 16, margin = margin(r = 20)),
        axis.text.y = element_text(size = 16, margin = margin(r = 5)),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.background = element_blank()
      ) +
      geom_text(stat = "count", aes(label = after_stat(count)), vjust = -0.5, size = 6) +
      scale_y_continuous(limits = c(0, max_count_round_with_margin), breaks = seq(0, max_count_round, by = 50))
  })

  # table with selected data
  output$df <- renderDT({
    data_used <- filtered_data()
    if ("Message" %in% colnames(data_used)) {
      datatable(data_used, selection = "single", options = list(dom = "rt", pageLength = 10), class = "stripe hover", rownames = FALSE)
    } else {
      data_used <- data_used %>% select(info, date_fin, ip, hostname, san)
      datatable(data_used, escape = FALSE, selection = "single", options = list(scrollX = TRUE, dom = "frtip", pageLength = 10), class = "stripe hover", rownames = FALSE)
    }
  })

  # button to download data
  output$download_data <- downloadHandler(
    filename = "data.csv", content = function(file) {
      data <- filtered_data()
      data <- data %>% select(date_fin, ip, hostname, san)
      write.csv(data, file, row.names = FALSE)
    }
  )

  # pop up when click on column "info" in table to display certificate info
  observeEvent(input$df_cell_clicked, {
    if (!is.null(input$df_cell_clicked$value) && !("Message" %in% colnames(filtered_data()))) {
      if (input$df_cell_clicked$col == 0) {
        selected_row <- filtered_data()[input$df_cell_clicked$row, , drop = FALSE]
        cert_data <- ssl_all[selected_row$ip == ssl_all$ip & selected_row$hostname == ssl_all$hostname, ]

        # subject name
        output$subject_name <- renderTable({
          cert_data$subject %>%
            select(CN) %>%
            dplyr::rename("Common Name" = CN)
        })

        # issuer name
        output$issuer_name <- renderTable({
          cert_data$issuer %>%
            select(C, O, CN) %>%
            dplyr::rename("Country" = C, "Organization" = O, "Common Name" = CN)
        })

        # validity
        output$validity <- renderUI({
          cert_data %>%
            select(date_debut, date_fin) %>%
            dplyr::rename("Not Before" = date_debut, "Not After" = date_fin) %>%
            kable(format = "html", row.names = FALSE) %>%
            kable_styling() %>%
            HTML()
        })

        # subject alt names
        output$subject_alt_names <- renderTable({
          san <- cert_data %>%
            select(san) %>%
            dplyr::rename("DNS Name" = san)
        })

        # serial number
        output$serial_number <- renderTable({
          serial_number <- cert_data %>%
            select(serialNumberHex) %>%
            dplyr::rename("Serial Number" = serialNumberHex)
        })

        showModal(modalDialog(title = "Informations du certificat", easyClose = TRUE, "Subject Name", tableOutput("subject_name"), tags$hr(style = "border-top: 1px solid #000;"), "Issuer Name", tableOutput("issuer_name"), tags$hr(style = "border-top: 1px solid #000;"), "Validity", uiOutput("validity"), tags$hr(style = "border-top: 1px solid #000;"), "Subject Alt Names", tableOutput("subject_alt_names"), tags$hr(style = "border-top: 1px solid #000;"), "Serial Number", tableOutput("serial_number"), footer = modalButton("Fermer")))
      }
    }
  })
}

shinyApp(ui, server)
