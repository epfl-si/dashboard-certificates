# package install
packages <- c("RSQLite", "DBI")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p)
    library(p, character.only = TRUE)
  }
}

con <- dbConnect(RSQLite::SQLite(), "./cmdb.sqlite")

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
