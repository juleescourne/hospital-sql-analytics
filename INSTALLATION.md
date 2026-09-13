> Parcours vérifié : `bash scripts/run_demo.sh` (Docker) ; exports et interprétations
> dans [results/README.md](results/README.md). Le script recrée uniquement la base
> dédiée `hospital_analytics`. L’index est utilisé, mais le plan montre un tri.

# Installation

Trois parcours, du plus rapide au plus fidèle.

| Parcours | Temps | Prérequis |
| --- | --- | --- |
| **Docker** — tout automatique | 3 min | Docker |
| **MySQL local** — vous avez déjà un serveur | 5 min | MySQL 8.0+ |
| **Jeu de données réel** — fidèle à l'analyse d'origine | 15 min | MySQL + compte Maven Analytics |

Les deux premiers utilisent un jeu synthétique généré localement, de structure
identique au jeu réel.

---

## Parcours 1 — Docker

```bash
git clone https://github.com/juleescourne/hospital-sql-analytics.git
cd hospital-sql-analytics

docker compose up -d                       # MySQL 8 + schéma appliqué automatiquement
python scripts/generate_sample_data.py     # 5 CSV + script de chargement
docker compose exec -T mysql mysql --local-infile=1 -uroot -phospital hospital_analytics < db/load_sample_data.sql
```

Puis lancez les requêtes :

```bash
docker compose exec -T mysql mysql -uroot -phospital hospital_analytics < queries/05_data_quality_checks.sql
```

Pour tout arrêter :

```bash
docker compose down          # conserve les données
docker compose down -v       # supprime aussi le volume
```

> Ce `docker-compose.yml` suit la configuration standard de l'image officielle MySQL
> mais **n'a pas pu être testé** : Docker n'était pas disponible dans
> l'environnement où il a été écrit. Signalez-moi tout écart.

---

## Parcours 2 — MySQL local

### Prérequis

| Outil | Version | Vérifier |
| --- | --- | --- |
| MySQL | 8.0 ou supérieur | `mysql --version` |
| Python | 3.10 ou supérieur | `python --version` |

MySQL 8.0 est requis : les fonctions fenêtres (`LEAD`, `ROW_NUMBER`, `NTILE`)
n'existent pas avant.

### 1. Créer le schéma

```bash
mysql -u root -p < db/schema.sql
```

Crée la base `hospital_analytics`, ses 5 tables, ses clés étrangères et ses 6 index.

### 2. Générer le jeu synthétique

```bash
python scripts/generate_sample_data.py
```

Écrit cinq CSV dans `data/` — 400 patients, 7 160 passages, 12 743 actes — ainsi
que `db/load_sample_data.sql`, prêt à l'emploi.

Options :

```bash
python scripts/generate_sample_data.py --patients 1000 --seed 7
```

### 3. Charger

```bash
mysql --local-infile=1 -u root -p hospital_analytics < db/load_sample_data.sql
```

L'option `--local-infile=1` est indispensable : `LOAD DATA LOCAL INFILE` est
désactivé par défaut, côté client comme côté serveur. Si le serveur la refuse :

```sql
SET GLOBAL local_infile = 1;
```

Le script affiche les volumes chargés en fin d'exécution.

---

## Parcours 3 — jeu de données réel

Le dataset **Hospital Patient Records** de Maven Analytics n'est pas redistribué
ici (licence).

1. Téléchargez-le sur <https://mavenanalytics.io/data-playground/hospital-patient-records>
2. Créez le schéma : `mysql -u root -p < db/schema.sql`
3. Importez les cinq CSV **dans cet ordre**, les clés étrangères l'imposent :

   ```text
   organizations.csv → payers.csv → patients.csv → encounters.csv → procedures.csv
   ```

   Via l'assistant d'import de MySQL Workbench, ou en adaptant
   `db/load_data.example.sql` avec vos chemins.

4. Contrôlez les volumes attendus :

   | Table | Lignes |
   | --- | ---: |
   | `patients` | 974 |
   | `encounters` | 27 891 |
   | `procedures` | 47 701 |
   | `payers` | 10 |
   | `organizations` | 1 |

---

## Vérifier l'installation

```bash
mysql -u root -p hospital_analytics < queries/05_data_quality_checks.sql
```

Sur le jeu synthétique, les contrôles doivent remonter les anomalies **injectées
volontairement** : 59 passages sans date de fin, 2 dates de fin antérieures au
début, 35 passages sans payeur. Un jeu parfaitement propre ne démontrerait rien.

---

## Problèmes courants

**`ERROR 1148: The used command is not allowed with this MySQL version`**
`local_infile` est désactivé. Relancez le client avec `--local-infile=1` et exécutez
`SET GLOBAL local_infile = 1;` côté serveur.

**`ERROR 1064` sur une fonction fenêtre**
Votre serveur est en MySQL 5.7 ou antérieur. `LEAD`, `ROW_NUMBER` et `NTILE`
exigent MySQL 8.0.

**`ERROR 1452: Cannot add or update a child row`**
Les fichiers ont été importés dans le mauvais ordre. Respectez l'ordre des
dépendances ci-dessus.

**`Incorrect date value: ''`**
Le serveur est en mode strict et une date vide a été insérée telle quelle.
`db/load_sample_data.sql` gère ce cas avec `NULLIF(@col, '')` — utilisez-le plutôt
qu'un import manuel.
