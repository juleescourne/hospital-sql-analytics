# Installation et reproduction

Prérequis : Python 3.10+, Bash et MySQL 8 (local ou Docker Compose avec `--wait`).

```bash
git clone https://github.com/juleescourne/hospital-sql-analytics.git
cd hospital-sql-analytics
bash scripts/run_demo.sh
```

Le script vérifie les empreintes de l’archive `data/source/hospital-patient-records.zip`, prépare les CSV, démarre MySQL et recrée la base dédiée **hospital_analytics**. Ne pas y conserver d’autres données. Le mot de passe du conteneur est uniquement une valeur locale de démonstration.

Ordre : tests Python → préparation Maven → création de la base → tests SQL sur de petits cas avec rollback → import Maven → rapprochement de l’import → sept fichiers SQL → sept CSV agrégés et JSON. Les chemins sont calculés à partir du dépôt courant ; aucun chemin Windows personnel n’est requis. Le mode Docker traduit les chemins préparés vers `/data/prepared/` dans le conteneur.

## MySQL existant

```bash
bash scripts/run_demo.sh --local
```

Configurer `MYSQL_BIN` (défaut `mysql`), `MYSQL_USER` (défaut `root`), `MYSQL_HOST` (défaut `127.0.0.1`), `MYSQL_PORT` (défaut `3306`) ou `MYSQL_SOCKET`. Le mot de passe peut être fourni via `MYSQL_PWD`, sans être versionné. Le client et le serveur doivent autoriser `local_infile`.

Ce parcours a été exécuté sur MySQL 8.0.46. GitHub Actions exécute aussi le mode local, puis compare les agrégats publiés avec les calculs reproduits. Le mode Docker utilise le même schéma et les mêmes CSV ; il n’a pas été exécuté dans l’environnement local de cette mise à jour.

## Fichiers source

L’archive incluse contient exactement les cinq CSV fournis, le dictionnaire et la citation. [Provenance, licence et empreintes](data/source/README.md). Les fichiers préparés sont ignorés par Git. Les dates UTC sont converties de ISO 8601 vers MySQL DATETIME ; les dates de fin et de décès vides deviennent NULL. Aucune anomalie n’est effacée.

Les décomptes de lignes et les sommes financières sont rapprochés après chargement. Les contraintes SQL seules ne prouvent pas l’absence de perte pendant l’import.

## Ancien générateur pédagogique

`python3 scripts/generate_sample_data.py` permet encore de créer un petit jeu artificiel pour expérimenter. Il est distinct des fichiers Maven et n’est plus utilisé par `run_demo.sh` ni par les résultats du portfolio. Ses quatre tests restent disponibles avec `python3 -m unittest discover -s tests -v`.

## Dépannage

- `local_infile` refusé : activer l’option sur le client et le serveur.
- Fonction fenêtre inconnue : utiliser MySQL 8.0 ou supérieur.
- Port 3306 occupé : adapter le port Docker ou utiliser le mode local.
- Empreinte différente : repartir de l’archive versionnée ; ne pas mettre à jour le manifeste pour masquer une modification inconnue.
