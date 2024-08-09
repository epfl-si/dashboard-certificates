library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(RSQLite)

con <- dbConnect(SQLite(), db_path)

create_table_server <- "
CREATE TABLE Server (
	id_ip INTEGER PRIMARY KEY AUTOINCREMENT,
	ip TEXT NOT NULL UNIQUE
);"
dbExecute(con, create_table_server)

create_table_user <- "
CREATE TABLE User (
	id_user INTEGER PRIMARY KEY AUTOINCREMENT,
	sciper INTEGER NOT NULL UNIQUE,
	cn TEXT NOT NULL,
	email TEXT NOT NULL
);"
dbExecute(con, create_table_user)

create_table_server_user <- "
CREATE TABLE Server_User (
	id_server_user INTEGER PRIMARY KEY AUTOINCREMENT,
	id_ip INTEGER NOT NULL,
	sciper INTEGER NOT NULL,
	rifs_flag INTEGER NOT NULL,
	adminit_flag INTEGER NOT NULL,
	CONSTRAINT Server_Server_User_FK FOREIGN KEY (id_ip) REFERENCES Server(id_ip) ON DELETE SET NULL ON UPDATE CASCADE,
	CONSTRAINT User_Server_User_FK FOREIGN KEY (sciper) REFERENCES Server(sciper) ON DELETE SET NULL ON UPDATE CASCADE
);"

dbExecute(con, create_table_server_user)

dbDisconnect(con_sqlite)
