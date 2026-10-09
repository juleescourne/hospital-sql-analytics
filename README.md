# Hospital SQL Analytics — activité, montants et qualité

**Projet personnel de Data Analyst junior — Jules Courné**
MySQL 8 · SQL analytique · Python · Contrôles qualité

Comment lire l’activité d’un établissement, les montants associés et leur couverture sans mélanger les indicateurs ? Cette étude répond à trois questions avec des requêtes SQL explicites et des résultats consultables.

**[Explorer les trois analyses dans le portfolio](https://juleescourne.github.io/portfolio-data-analyst/#/hospital)** · **[Lire les résultats](results/README.md)** · **[Voir les requêtes de synthèse](queries/07_portfolio_summary.sql)**

Les données sont **entièrement synthétiques** : 400 patients, 7 794 passages et 13 839 actes, avec une graine fixe. Les règles du générateur déterminent les distributions ; les résultats ne décrivent pas un établissement réel.

## Trois questions, trois lectures

| Question | Résultat du jeu de démonstration | Lecture |
| --- | --- | --- |
| Quels passages concentrent les volumes et les durées ? | Ambulatoire : 44,62 % des passages. Hospitalisation : 2,86 %, avec une durée médiane de 75,58 h. | Distinguer le nombre de passages de leur durée ; celle-ci ne mesure pas le travail soignant. |
| Quelle part des montants est couverte par les payeurs ? | 67,37 %, calculés comme somme des couvertures / somme des montants. | Les volumes et le profil des passages comptent ; ce taux ne classe pas la qualité des assureurs. |
| Quelles anomalies limitent la lecture ? | 64 fins manquantes, 2 durées négatives et 38 payeurs non renseignés. | Durées calculées sur 7 728 passages ; montants sur 7 794. Les anomalies ne sont pas remplacées par zéro. |

## Ce que j’ai réalisé

- Modélisation de cinq tables avec clés étrangères, types `DECIMAL` pour les montants et index.
- Contrôles de complétude, dates, doublons et cohérence entre actes, passages et patients.
- Jointures, CTE et fonctions fenêtres : `LEAD`, `LAG`, `ROW_NUMBER`, `DENSE_RANK`, `NTILE`, cumuls et moyennes mobiles.
- Calcul d’une médiane par classement, d’un taux de couverture pondéré et de cohortes d’activité.
- Quatre tests Python et sept groupes de tests MySQL sur des cas dont les résultats sont connus.
- Restitution des résultats avec leurs dénominateurs, leur interprétation et les vérifications à poursuivre.

## Reproduire

Prérequis : Docker Compose avec `--wait`, Python 3.10+ et Bash.

```bash
git clone https://github.com/juleescourne/hospital-sql-analytics.git
cd hospital-sql-analytics
bash scripts/run_demo.sh
```

Cette commande recrée la base **réservée à la démonstration** `hospital_analytics`, génère et charge les données, exécute les tests puis les sept fichiers SQL. Ne pas utiliser cette base pour conserver d’autres données. Les tests SQL utilisent une transaction annulée et n’altèrent pas les résultats de démonstration.

Pour un serveur MySQL 8 existant : `bash scripts/run_demo.sh --local`. Les variables de connexion sont décrites dans [INSTALLATION.md](INSTALLATION.md). GitHub Actions exécute le mode local sur le serveur MySQL 8 du runner Ubuntu : [workflow](.github/workflows/sql-demo.yml).

Pour vérifier seulement le générateur, sans base ni dépendance Python supplémentaire :

```bash
python3 -m unittest discover -s tests -v
```

## Parcourir les fichiers

| Fichier | Rôle |
| --- | --- |
| [05 — qualité](queries/05_data_quality_checks.sql) | Contrôles à exécuter avant l’analyse |
| [01 — exploration](queries/01_data_exploration.sql) | Volumes, dates, répartition des classes |
| [02 — patients](queries/02_patient_analytics.sql) | Profils et activité enregistrée |
| [03 — passages](queries/03_encounter_analytics.sql) | Durées, retours, montants et couverture |
| [04 — actes](queries/04_procedure_financial_analytics.sql) | Fréquence et concentration des coûts des actes |
| [06 — fonctions fenêtres](queries/06_window_functions_cohorts.sql) | Classements, calendrier mensuel et cohortes |
| [07 — synthèse métier](queries/07_portfolio_summary.sql) | Trois tableaux et un bilan pour le portfolio |
| [Résultats et interprétations](results/README.md) | Sorties MySQL, CSV et limites |
| [Tests SQL](scripts/check_sql.py) | Vérification des vraies requêtes sur de petits cas |
| [Dictionnaire](docs/data_dictionary.md) | Grain, colonnes et règles des indicateurs |

## Trois choix à expliquer en entretien

**Calculer le passage suivant avant de filtrer.** Un passage sans date de fin possède tout de même une date de début. Il reste dans la chronologie de `LEAD` et `LAG`. Le retour est ensuite retenu entre la fin valide du passage précédent et exactement 30 × 24 heures plus tard, bornes incluses. Ce comptage n’est pas un taux clinique de réadmission.

**Pondérer la couverture par les montants.** `SUM(PAYER_COVERAGE) / SUM(TOTAL_CLAIM_COST)` mesure la part du montant total couverte. La moyenne des ratios répondrait à une autre question en donnant le même poids à chaque passage.

**Distinguer un zéro d’une période non observée.** Le calendrier mensuel inclut les mois sans passage dans la fenêtre du fichier. Les cohortes affichent les années sans activité à zéro, mais pas les années futures. La dernière année peut être partielle : les cohortes ne prouvent ni fidélité ni qualité des soins.

## Limites

Les paramètres sont pédagogiques, sans calibration clinique. Les montants des actes et des passages sont analysés séparément et ne sont pas additionnés. Un montant non couvert ne prouve pas une dette du patient, une perte ou une marge. Les distributions par âge ou groupe démographique n’autorisent aucune conclusion clinique.

L’index apparaît dans le [plan d’exécution](results/explain.txt), suivi d’un tri. Aucun gain de performance n’est annoncé sans mesure comparative.

Le jeu Maven Analytics d’origine n’est pas redistribué ; les résultats publiés proviennent du générateur synthétique du dépôt. Code sous [licence MIT](LICENSE).
