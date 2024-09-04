# dashboard_certificates

Le but de ce projet est de visualiser les dates d'échéances des certificats SSL ainsi que les personnes responsables dans le but d'anticiper le renouvellement des certificats.

La commande principale `make up` permet de :
- créer les volumes utilisés par docker
- démarrer un container pour elasticsearch
- copier les données dans un elasticsearch de dev
- créer et alimenter un schéma dans SQLite
- démarrer un container pour shiny
- donner accès au dashboard

## Pré-requis

- Docker
- R
- SQLite3

## Marche à suivre

1) Cloner le repo.
2) Placer les fichiers JSON contenant les données de production à importer dans le dossier *prod_to_dev/internal_data* (cmdb.json et ssl.json). -> TODO : version quand import direct depuis la prod
3) FIXME : Toujours nécessaire ou non ? -> Formater le fichier ssl.json avec `make reformat_ssl_json`.
4) Copier le fichier *.env_default* et le renommer en *.env* -> TODO : version qui pointe sur elasticsearch de prod (*.env_advanced*)
5) FIXME : Problème de charge (mémoire, CPU, ...) sur certains ordis et utiliser `make elasticsearch_healthy` pour s'assurer que l'état du cluster n'est pas *red* sinon KO.
6) `make up` pour version standard et sinon TODO

## TODO / FIXME

- fixer lancements des scripts R depuis Makefile (dans et hors docker)
- Makefile -> ne doit pas poser problème si même commande relancée plusieurs fois de suite (KO avec génération du token pour `make token`)
- schéma UML de la base de données et de cmdb + ssl à la base
- utiliser les namespaces dans le code R (`ns()`) pour délimiter influence des variables
