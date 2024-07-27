# packages activation
library(here)

here::i_am("lib.R")

source(here("lib.R"))
source(here("env.R"))

library(RSQLite)

con <- dbConnect(SQLite(), db_path)

# TODO : cle primaire doit etre ip et fqdn, pas l'un ou l'autre !

create_table_serveur <- "
CREATE TABLE Serveur (
	id_ip_adr INTEGER PRIMARY KEY AUTOINCREMENT,
	fqdn TEXT NOT NULL,
	ip TEXT NOT NULL
);"

dbExecute(con, create_table_serveur)

create_table_personne <- "
CREATE TABLE Personne (
	sciper INTEGER NOT NULL,
	cn TEXT NOT NULL,
	email TEXT NOT NULL,
	CONSTRAINT Personne_PK PRIMARY KEY (sciper)
);"

dbExecute(con, create_table_personne)

create_table_serveur_personne <- "
CREATE TABLE Serveur_Personne (
	id_serv_pers INTEGER PRIMARY KEY AUTOINCREMENT,
	fqdn TEXT NOT NULL,
	sciper INTEGER NOT NULL,
	rifs_flag INTEGER NOT NULL,
	adminit_flag INTEGER NOT NULL,
	CONSTRAINT Serveur_Serveur_Personne_FK FOREIGN KEY (fqdn) REFERENCES Serveur(fqdn) ON DELETE SET NULL ON UPDATE CASCADE,
	CONSTRAINT Personne_Serveur_Personne_FK FOREIGN KEY (sciper) REFERENCES Serveur(sciper) ON DELETE SET NULL ON UPDATE CASCADE
);"

dbExecute(con, create_table_serveur_personne)
