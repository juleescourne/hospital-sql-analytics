# Installation et reproduction

## Parcours Docker

Prérequis : Docker Compose avec `--wait`, Python 3.10+ et Bash.

```bash
git clone https://github.com/juleescourne/hospital-sql-analytics.git
cd hospital-sql-analytics
bash scripts/run_demo.sh
```

Le script génère les CSV **avant** le montage Docker, attend le serveur final et recrée `hospital_analytics`. Cette base est réservée à la démonstration. Le mot de passe du conteneur est une valeur locale de démonstration.

Ordre : tests Python → génération → chargement → tests SQL avec rollback → sept fichiers SQL → exports métier. Les données agrégées sont écrites dans `results/`. Le workflow GitHub exécute le même pipeline avec `--local` sur le serveur MySQL 8 du runner Ubuntu. Il ne dépend pas du téléchargement d’une image Docker.

```bash
docker compose down      # arrêter, conserver le volume
```

## Parcours MySQL 8 local

Le client et le serveur doivent autoriser `local_infile`. Le script utilise `MYSQL_BIN` (défaut `mysql`), `MYSQL_USER` (défaut `root`), `MYSQL_HOST` (défaut `127.0.0.1`), `MYSQL_PORT` (défaut `3306`) et, si fourni, `MYSQL_SOCKET`. Le mot de passe peut être fourni via `MYSQL_PWD` dans l’environnement local ; ne pas le versionner.

```bash
bash scripts/run_demo.sh --local
```

Ce mode recrée également la base dédiée `hospital_analytics`. Les autres bases ne sont pas ciblées.

## Générateur seul

```bash
python3 -m unittest discover -s tests -v
python3 scripts/generate_sample_data.py
```

Par défaut : graine 42, 400 patients, 7 794 passages, 13 839 actes. Les options `--patients` et `--seed` permettent d’explorer d’autres jeux ; les chiffres publiés correspondent uniquement aux valeurs par défaut. Le lanceur complet utilise ces valeurs pour reproduire la synthèse.

Les anomalies intentionnelles sont : 64 dates de fin absentes, 2 durées négatives, 3 durées nulles et 38 payeurs manquants. Les passages avant naissance et après décès doivent être absents. Une durée nulle est signalée et conservée.

## Adapter à des fichiers externes

Le jeu Hospital Patient Records de Maven Analytics n’est pas fourni. `db/load_data.example.sql` sert de point de départ à adapter aux fichiers et à leurs règles. Charger dans l’ordre : organizations, payers, patients, encounters, procedures. Contrôler les fichiers avant import : les contraintes en base ne prouvent pas qu’aucune ligne n’a été rejetée ou convertie au chargement.

Les sorties de cette version sont celles du jeu synthétique, pas une validation du jeu externe.

## Dépannage

- `local_infile` refusé : activer l’option sur le serveur et le client ; le conteneur fourni la configure.
- Fonction fenêtre non reconnue : utiliser MySQL 8.0 ou supérieur.
- Port 3306 occupé : adapter le port publié dans `docker-compose.yml` ou utiliser le mode local.
- Date vide : le chargeur généré utilise `NULLIF` pour convertir les champs prévus en `NULL`.
