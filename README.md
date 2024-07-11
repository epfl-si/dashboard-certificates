# dashboard_certificates

Création d'un dashboard pour visualiser ses propres certificats ayant une échéance à court terme.

## Pré-requis

- Docker
- R
- DBeaver

## Marche à suivre

1) Cloner le repo.
2) Placer les fichiers JSON contenant les données de production à importer dans le dossier *prod_to_dev/internal_data* (cmdb.json et ssl.json). -> TODO : version quand import direct depuis la prod
3) FIXME : Toujours nécessaire ou non ? -> Formater le fichier ssl.json avec `make reformat_ssl_json`.
4) Renommer le fichier *.env_default* en *.env* -> TODO : version qui pointe sur elasticsearch de prod (*.env_advanced*)
5) FIXME : Problème de charge (mémoire, CPU, ...) sur certains ordis et utiliser `make elasticsearch_healthy` pour s'assurer que l'état du cluster n'est pas *red* sinon KO.
6) `make up` pour version standard et sinon TODO

## TODO / FIXME

- add_cmdb_data.R (voir FIXMEs) -> correspondance entre données de ssl et cmdb KO
- fixer lancements des scripts R depuis Makefile (dans et hors docker)
- dashboard -> finir tableau (pour l'instant ébauche de tableau avec toutes les données), créer page de détails et créer vues différentes en fonction du sciper / fonction du user
- Makefile -> ne doit pas poser problème si même commande relancée plusieurs fois de suite (KO avec génération du token pour `make token`)
