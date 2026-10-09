# Trois analyses sur des données synthétiques

Résultats recalculés avec MySQL 8.0.46, graine 42 : **400 patients, 7 794 passages et 13 839 actes**. La [démo du portfolio](https://juleescourne.github.io/portfolio-data-analyst/#/hospital) utilise les exports ci-dessous.

Les chiffres décrivent les règles du générateur. Ils ne mesurent pas l’activité d’un hôpital réel.

## 1. Volumes, durées et montants

L’ambulatoire représente **3 478 passages, soit 44,62 %** du volume. L’hospitalisation ne représente que **223 passages, soit 2,86 %**, mais concentre **32,96 %** des montants des passages.

Sur les durées valides, la médiane d’hospitalisation atteint **75,58 h**, contre **0,99 h** pour l’ambulatoire. La moyenne d’hospitalisation est de **86,01 h**, au-dessus de sa médiane.

**Interprétation :** le nombre de passages ne résume ni leur durée ni les montants associés. Une durée entre entrée et sortie ne représente pas des heures de travail soignant.

**Suite proposée :** avec des données réelles, examiner dispersion, simultanéité des passages et ressources avant une décision de capacité. Les écarts sont ici déterminés par la simulation.

[Tableau complet · CSV](activity.csv) · [Requête 1](../queries/07_portfolio_summary.sql)

## 2. Part des montants couverte

Le montant total des passages est **14 046 530,87 USD**, dont **9 463 279,12 USD** couverts, soit **67,37 %**. Le taux est le rapport des sommes, pas une moyenne simple des ratios individuels.

**38 passages** n’ont pas de payeur renseigné. Ils restent inclus dans le calcul global : leurs montants couverts existent. Leur catégorie ne doit pas être confondue avec `NO_INSURANCE`.

**Interprétation :** le montant non couvert dans le fichier ne démontre ni une dette patient, ni une perte ou une marge. Les paramètres des payeurs sont simulés ; ces résultats ne comparent pas les performances réelles d’assureurs.

**Suite proposée :** vérifier l’identité des payeurs, le sens des montants et le périmètre contractuel avant d’utiliser ce ratio dans un reporting réel. Les coûts des actes sont étudiés séparément et ne sont pas additionnés aux montants des passages.

[Tableau par payeur · CSV](coverage.csv) · [Requête 2](../queries/07_portfolio_summary.sql)

## 3. Qualité et exclusions

| Signal | Nombre | Traitement |
| --- | ---: | --- |
| Date de fin absente | 64 | Exclure des durées ; conserver le début dans la chronologie |
| Durée négative | 2 | Exclure des durées et comme passage de référence du retour |
| Durée nulle | 3 | Signaler, conserver |
| Payeur absent | 38 | Conserver dans une catégorie distincte |
| Passage avant naissance | 0 | Contrôle ajouté au générateur et au SQL |
| Passage ou fin après décès | 0 | Contrôler au jour près, les dates de décès n’ayant pas d’heure |
| Discordance patient entre acte et passage | 0 | Vérifier en plus des clés étrangères |

Les durées utilisent **7 728 passages** ; les volumes et montants en utilisent **7 794**. Les motifs peuvent se chevaucher et ne doivent pas être additionnés pour dénombrer des passages défectueux. Une fin manquante ne signifie pas nécessairement une hospitalisation en cours.

[Compteurs et dénominateurs · CSV](quality.csv) · [Requête 3](../queries/07_portfolio_summary.sql)

## Vérification

- Quatre tests Python : chronologie et relations, anomalies attendues, reproductibilité, population invalide.
- Sept groupes de tests MySQL sur les vraies requêtes : passage suivant sans fin, bornes exactes du retour, couverture pondérée/coût nul, mois vide, cohorte sans activité, dates hors de la vie du patient, médiane et dénominateurs.
- Rapprochement des volumes et montants entre les exports et le bilan global.
- Vérification indépendante des effectifs, montants, moyennes et médianes à partir des CSV générés lors de cette mise à jour.

Le pipeline [GitHub Actions](../.github/workflows/sql-demo.yml) réexécute tests et calculs. Les tableaux de synthèse versionnés sont comparés aux résultats régénérés. Les [tests SQL](../scripts/check_sql.py) s’exécutent dans une transaction annulée.

[Bilan global · CSV](overview.csv) · [Données du portfolio · JSON](portfolio.json) · [Version MySQL](environment.tsv)

## Autres analyses et plan d’exécution

Les sept TSV contiennent plusieurs tableaux successifs. Le retour à 30 jours reste un comptage exploratoire : il ne définit pas une population clinique éligible ni une fenêtre complète de suivi. Les cohortes conservent les zéros observés, sans inventer des années futures.

[explain.txt](explain.txt) montre un parcours de l’index `idx_encounters_patient_start`, suivi d’un tri. Les statistiques de table sont actualisées avant ce plan ; ses estimations peuvent varier selon l’environnement. Aucun gain de performance n’est annoncé.
