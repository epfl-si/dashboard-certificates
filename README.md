# dashboard_certificates

Le but de ce projet est de visualiser les dates d'échéances des certificats SSL dans le but d'anticiper leur renouvellement.

## Marche à suivre

### Pré-requis

Les programmes suivants doivent être installés :

- Docker
- R
- SQLite3

### Exécution

Suivre la marche à suivre ci-dessous pour initialiser l'environnement ou exécuter `make up` pour démarrer l'environnement (après initialisation).

1) Cloner le repo.
2a) Obtenir les données de test au format json et placer ces fichiers (cmdb.json et ssl.json) sous *./prod_to_dev/internal_data*.
2b) Exécuter la commande `make data_copy` pour obtenir des données de test depuis la prod.
3) **TODO : reproduire l'erreur** Exécuter la commande `make reformat_ssl_file` pour formater le fichier *ssl.json* précédemment importé.
4) Exécuter la commande `make init` (voir détails de la commande ci-dessous).
5) Aller sur http://localhost:8183 -> **TODO : fixer la copie du fichier *.env_default* en *.env* et FIXME : comment gérer avec Keybase (voir *.env_advanced*) ?**

#### Détails de la commande `make init`

La commande `make init` permet de :
- vérifier que les fichiers contenant les données de test soient présents
- créer les volumes utilisés par docker
- démarrer un container pour elasticsearch
- copier les données dans un elasticsearch de dev
- créer et alimenter un schéma dans SQLite
- démarrer un container pour shiny

### Optionnel

Il est possible d'accéder à une instance kibana pour visualiser les données présentes dans l'elasticsearch de dev en exécutant la commande `make kibana`.

# TODO : modifier makefile en conséquence

### Possibles problèmes

- Créer un cluster sur Elasticsearch demande passablement de mémoire. En cas d'erreur, vérifier l'état du cluster en exécutant `make elasticsearch_healthy`. Si l'état indique *red*, **FIXME : trouver une solution**.
- Pour tout autre problème constaté, merci d'ouvrir une issue sur github.

# FIXME : ajouter informations concernant la prod (ansible et autres) ?
