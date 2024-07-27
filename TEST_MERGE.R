# packages activation
library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(dplyr)
library(elastic)
library(jsonlite)
library(RSQLite)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import data from cmdb index
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"
# import data from ssl index
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))

# but est de filtrer l'index cmdb pour ensuite alimenter les tables dans sqlite
# avant : filtre sur ip mais certificat rattache a fqdn/hostname donc filtre sur fqdn/hostname a la place
# maintenant : fqdn != hostname car certificat rattache a un hostname qui est different d'un fqdn (parfois) donc rester sur l'idee de l'ip
# FIXME : quel est le role des alternatives names dans tout ça ? est-ce qu'ils peuvent apparaitrent comme nouvelles lignes dans la cmdb (avec fqdn dans la liste des alternatives names pour ceux-ci) ?
# TODO : alternative name = meme certificat pour hostname different, possible d'ajouter ligne pour chercher dans hostname avec alternatives names mais dans un deuxieme temps

# FIXME : semi pour ne garder que colonnes du premier df et que lignes similaires entre les 2 dfs

# tentative de filtrer avec right
cmdb_data_filtred_right <- right_join(cmdb_data, ssl_data, by = c("fqdn" = "hostname")) # centaine de lignes en trop (2628) car doublons
# doublons sur ip pour ssl mais pas cmdb
ip_ssl <- ssl_data %>% group_by(ipv4) %>% mutate(nb_doublons = n()) %>% select(ipv4, nb_doublons)
ip_cmdb <- cmdb_data %>% group_by(ip) %>% mutate(nb_doublons = n()) %>% select(ip, nb_doublons)
# recherche des doublons sur hostname / fqdn (doublons uniquement dans cmdb)
doublons_ssl <- ssl_data$hostname %>% unique() # pas de doublon dans ssl car 2556
doubons_cmdb <- cmdb_data$fqdn %>% unique() # doublons dans cmdb car 87557 au lieu de 88209
cmdb_recherche_doublons <- cmdb_data %>% group_by(fqdn) %>% mutate(nb_doublons = n()) %>% select(fqdn, nb_doublons)
# verification de la recherche
cmdb_doublons_unique <- cmdb_recherche_doublons %>% distinct()
total <- sum(cmdb_doublons_unique$nb_doublons) # 88209 donc resultat fiable
# filtre sur les doublons
fqdn_unique <- cmdb_doublons_unique %>% filter(nb_doublons == 1) # 86919 donc 638 (87557 - 86919) fqdns non uniques
fqdn_non_unique <- cmdb_doublons_unique %>% filter(nb_doublons > 1) # 638 fqdns non uniques donc ok
# FIXME : que represente la difference entre 88209 et 87557 (= 652), voir ligne 36 ? pourquoi ne correspond pas au 638 fqdn non uniques de la ligne 43 ???
# a cause du fait que meme fqdn sur ip differentes ???
# causes doublons (exemple) :
library(stringr)
doublons_type_ip_variable <- cmdb_data %>% group_by(fqdn) %>% mutate(nb_doublons = n()) %>% select(ip, fqdn, nb_doublons) %>% filter(str_detect(fqdn, "ditsbsrv9.epfl.ch"), nb_doublons > 1)
doublons_ip_hors_epfl <- cmdb_data %>% group_by(fqdn) %>% mutate(nb_doublons = n()) %>% select(ip, fqdn, nb_doublons) %>% filter(fqdn == 'dii-solar-trih.epfl.ch')
# plus de cas peut-etre...
doublons_dans_epfl <- cmdb_data %>% filter(str_detect(ip, "128.")) %>% group_by(fqdn) %>% mutate(nb_doublons = n()) %>% select(ip, fqdn, nb_doublons) # pas de doublon si ip de l'epfl

# FIXME : lier ssl et cmdb correctement car si que ip alors ne prend pas en compte hostname et si les 2 alors passe a cote si fqdn et hostname ecrits differemment
merge <- cmdb_data %>% inner_join(ssl_data, by = c("ip" = "ipv4", "fqdn" = "hostname"))
# probleme avec ca (lors du remplissage dans sqlite) : personne (reste a determiner si rifs ou adminit) n'est pas forcement responsable de l'ensemble de tous les certificats present sur une meme machine
ssl_cert_par_ip <- ssl_data %>% group_by(ipv4) %>% mutate(nb_certificats = n()) %>% select(ipv4, hostname, nb_certificats)
# 128.178.222.197 -> 513 certificats
# 128.178.219.230 -> 128 certificats
# FIXME : pourquoi autant de certificats sur une meme ip ? voir wildcard ...
# recherche a resoudre probleme de la ligne 55
ssl_filter_one_ip <- ssl_data %>% filter(ipv4 == "128.178.222.197") # 513
cmdb_filter_one_ip <- cmdb_data %>% filter(ip == "128.178.222.197") # 1
ssl_filter_one_hostname <- ssl_filter_one_ip %>% filter(str_detect(hostname, "app-pub-os-exopge")) # present (seul sur 513 certificats)

# TOOD : subject$CN -> *.epfl.ch pour wildcard
