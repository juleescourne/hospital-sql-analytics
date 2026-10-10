# Hospital SQL Analytics — jeu public Maven / Massachusetts

**Projet personnel de Data Analyst junior — Jules Courné**

MySQL 8 · SQL analytique · Python · Qualité des données

**Quels passages concentrent l’activité et les montants, et quels contrôles faut-il effectuer avant de restituer ces indicateurs ?**

L’analyse utilise les fichiers publics [Hospital Patient Records de Maven Analytics](https://mavenanalytics.io/data-playground/hospital-patient-records) : **974 patients, 27 891 passages et 47 701 actes**. Maven indique une origine **SyntheticMass / Synthea** et une licence **Public Domain**. Ces données sont synthétiques : elles ne décrivent pas des patients réels ni les performances réelles du Massachusetts General Hospital.

**[Explorer la démo](https://juleescourne.github.io/portfolio-data-analyst/#/hospital)** · **[Lire l’analyse](results/README.md)** · **[Requêtes de synthèse](queries/07_portfolio_summary.sql)** · **[Provenance et empreintes](data/source/manifest.json)**

## Trois résultats à retenir

| Question | Résultat vérifié dans MySQL | Lecture |
| --- | --- | --- |
| Où se concentre l’activité ? | L’ambulatoire représente 44,95 % des passages et 35,74 % des montants. | Distinguer volumes, durées et montants ; un passage n’est pas nécessairement une hospitalisation. |
| Quelle part des montants est couverte ? | 31,10 M USD sur 101,51 M USD, soit **30,63 %**. | Calculer le rapport des sommes ; ne pas additionner coûts des actes et montants des passages. |
| La moyenne des durées est-elle représentative ? | Ambulatoire : moyenne **9,48 h**, médiane **0,25 h**. Sans les 5 passages de plus de 24 h, moyenne **0,92 h**. | Examiner les valeurs extrêmes avant d’utiliser la moyenne ; le seuil de 24 h est un diagnostic, pas une règle clinique. |

Les contrôles détectent aussi **57 passages avec un début ou une fin après décès** (53 commencent après décès). En les excluant dans un scénario séparé, la couverture passe de 30,63 % à **30,58 %**. Les données source restent intactes. La période finit le **5 février 2022** : 2022 n’est pas comparable à une année complète.

## Ce que j’ai réalisé

- Préparation des CSV, vérification de leurs empreintes et chargement de cinq tables relationnelles.
- Conversion explicite des dates UTC et rapprochement des cinq volumes et de trois sommes financières entre CSV et MySQL.
- Contrôles des clés, doublons, dates, montants et cohérence patient–passage–acte.
- Jointures, agrégations, CTE et fonctions fenêtres ; moyenne, médiane, couverture pondérée et sensibilité aux anomalies.
- Restitution de trois analyses avec graphiques interactifs, constats, limites et suites proposées.
- Huit groupes de tests SQL sur des cas connus ; GitHub Actions recalcule les agrégats publiés.

## Reproduire

Prérequis : Docker Compose avec `--wait`, Python 3.10+ et Bash.

```bash
git clone https://github.com/juleescourne/hospital-sql-analytics.git
cd hospital-sql-analytics
bash scripts/run_demo.sh
```

Le script recrée la base **dédiée** `hospital_analytics`, vérifie les calculs puis importe l’archive publique incluse dans `data/source/`. Aucun compte Maven n’est nécessaire pour reproduire cette version. Les fichiers d’origine sont conservés, avec dictionnaire et citation Synthea ; leur archive est un conditionnement local documenté, pas l’archive de téléchargement officielle.

Sur un serveur MySQL 8 existant : `bash scripts/run_demo.sh --local`. Les paramètres sont décrits dans [INSTALLATION.md](INSTALLATION.md). Ne pas stocker d’autres données dans cette base, car elle est recréée.

## Parcourir le projet

| Fichier | Rôle |
| --- | --- |
| [Préparation Maven](scripts/prepare_maven.py) | Empreintes, relations, dates UTC et chargeur |
| [Rapprochement de l’import](scripts/check_source_import.py) | Volumes et montants comparés aux CSV |
| [05 — qualité](queries/05_data_quality_checks.sql) | Contrôles avant interprétation |
| [01 — exploration](queries/01_data_exploration.sql) | Volumes, période et classes |
| [02 — patients](queries/02_patient_analytics.sql) | Profils et activité enregistrée |
| [03 — passages](queries/03_encounter_analytics.sql) | Durées, retours et couverture |
| [04 — actes](queries/04_procedure_financial_analytics.sql) | Fréquence et coûts des actes |
| [06 — fenêtres](queries/06_window_functions_cohorts.sql) | Classements, calendrier, cohortes |
| [07 — restitution](queries/07_portfolio_summary.sql) | Sept tableaux de synthèse et de sensibilité |
| [Résultats commentés](results/README.md) | Constats, interprétations et limites |
| [Tests SQL](scripts/check_sql.py) | Cas simples et résultats attendus |

## Trois choix à expliquer en entretien

**Contrôler avant de supprimer.** Les durées sont calculables sur les 27 891 passages, mais cela ne prouve pas leur cohérence métier. Les passages après décès et les durées longues sont signalés, puis étudiés séparément. Le tableau principal décrit le fichier tel qu’il est enregistré.

**Pondérer la couverture.** `SUM(PAYER_COVERAGE) / SUM(TOTAL_CLAIM_COST)` mesure une part du montant total. Une moyenne de ratios donnerait un poids identique à chaque passage. Le champ `NO_INSURANCE` est renseigné : il ne s’agit pas d’un payeur manquant.

**Ne pas surinterpréter une chronologie.** `LEAD` est calculé avant le filtrage des fins manquantes pour retrouver le passage suivant. Un retour dans les 30 jours reste exploratoire : les fichiers ne permettent pas de construire un taux clinique de réadmission validé.

## Périmètre et limites

Les montants sont ceux du fichier, en USD. Un montant non couvert ne prouve pas un reste à charge patient, une perte ou une marge. La couverture par payeur dépend de la simulation et du type de passages ; elle ne classe pas des assureurs réels. Les heures entre `START` et `STOP` ne mesurent pas le travail soignant.

Le générateur pédagogique du dépôt est conservé uniquement comme outil de test ; **il ne produit plus les résultats publiés**. Les anciens chiffres de 400 patients et 7 794 passages sont remplacés par l’analyse Maven. Code sous [licence MIT](LICENSE), données publiques selon la [source Maven](data/source/README.md).
