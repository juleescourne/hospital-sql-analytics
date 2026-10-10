# Analyse du jeu public Maven Hospital Patient Records

**974 patients, 27 891 passages et 47 701 actes**, recalculés dans MySQL 8 à partir des CSV Maven / SyntheticMass. Le jeu est public et synthétique. Il ne permet pas de conclure sur les performances réelles d’un hôpital ou d’un assureur.

[Démo interactive](https://juleescourne.github.io/portfolio-data-analyst/#/hospital) · [Source et empreintes](../data/source/README.md) · [SQL de restitution](../queries/07_portfolio_summary.sql)

## 1. Activité : distinguer volumes, durées et montants

L’ambulatoire concentre **12 537 passages (44,95 %)** et **35,74 % des montants**. Les soins urgents représentent **13,14 % des passages** mais **23,00 % des montants**. Les 1 135 hospitalisations représentent 4,07 % des passages et 8,68 % des montants.

La durée médiane est de **15 minutes** en ambulatoire et consultation externe, contre **24 heures** en hospitalisation. La moyenne ambulatoire atteint pourtant **9,48 h** : **5 passages sur 12 537** dépassent 24 h et concentrent environ 90,26 % de la somme des durées de cette classe. Le maximum atteint **44 930 h**, plus de cinq ans. Ces enregistrements ne doivent pas être interprétés automatiquement comme une occupation continue d’un lit.

| Classe | Moyenne enregistrée | Médiane | Passages > 24 h | Moyenne sans ces passages |
| --- | ---: | ---: | ---: | ---: |
| Ambulatoire | 9,48 h | 0,25 h | 5 | 0,92 h |
| Consultation externe | 5,88 h | 0,25 h | 7 | 0,28 h |

Le seuil de 24 h sert uniquement à mesurer la sensibilité dans ces deux classes. Il ne valide pas une règle clinique de nettoyage et n’est pas appliqué aux hospitalisations. Les fichiers source et les indicateurs principaux ne sont pas modifiés.

**Suite proposée :** vérifier la signification de `START` et `STOP` pour ces libellés, puis décider avec un référent métier des exclusions à appliquer. Utiliser la médiane et montrer la dispersion avant une décision de capacité.

La série annuelle atteint 3 885 passages en 2014 et 3 530 en 2021. **2022 ne contient que 220 passages jusqu’au 5 février** : ce nombre ne démontre pas une baisse annuelle d’activité. Les variations du nombre de patients présents dans le jeu limitent aussi l’interprétation des évolutions.

[Classes · CSV](activity.csv) · [Années · CSV](annual.csv) · [Sensibilité des durées · CSV](sensitivity.csv)

## 2. Couverture : calculer la part du montant total

Les passages représentent **101 514 375,52 USD**, dont **31 097 506,99 USD** couverts : **30,63 %**. Calcul : `SUM(PAYER_COVERAGE) / SUM(TOTAL_CLAIM_COST)`.

`NO_INSURANCE` correspond à **8 807 passages** et **49 259 290,16 USD** de montants, avec une couverture nulle. Cette catégorie est renseignée ; aucun identifiant de payeur ne manque dans l’import. Medicare est le premier payeur en volume, avec 11 371 passages. Les couvertures très faibles ou nulles de certains payeurs demanderaient une vérification du modèle Synthea et des conventions du fichier avant toute interprétation.

**Interprétation :** les montants couverts ne sont pas des paiements encaissés attestés. Le montant non couvert n’est pas nécessairement une dette du patient ou une perte hospitalière. Les coûts des actes sont déjà des lignes de coût liées aux passages et ne sont pas ajoutés à `TOTAL_CLAIM_COST`.

**Suite proposée :** vérifier les définitions, distinguer absence d’assurance et couverture nulle d’un payeur nommé, puis comparer des types de passages comparables. Aucune performance réelle d’assureur n’est déduite de ces données simulées.

[Couverture par payeur · CSV](coverage.csv)

## 3. Qualité : un fichier complet peut contenir des incohérences

Les cinq volumes chargés et les trois sommes financières sont identiques aux CSV source. Les clés et relations sont contrôlées avant et après chargement. Aucun identifiant primaire dupliqué, orphelin, montant négatif, dépassement de couverture ou désaccord patient entre acte et passage n’a été détecté.

Les dates de début et de fin sont renseignées et ordonnées pour les **27 891 passages**. Cependant :

- **57 passages** ont un début ou une fin après la date de décès, dont **53 commencent après décès**. Ces compteurs se recouvrent : ne pas les additionner.
- **12 passages ambulatoires ou externes** dépassent 24 h, sur 18 837 passages de ces deux classes.
- **19 541 motifs de passage ne sont pas renseignés** ; selon le dictionnaire, le motif est conditionnel. Il ne s’agit donc pas automatiquement d’une erreur à imputer.

Le tableau principal conserve toutes les observations, pour décrire le fichier brut. Un scénario excluant les 57 passages hors de la vie du patient donne **27 834 passages**, **101 257 677,13 USD** et une couverture de **30,58 %**, contre 30,63 % initialement. Ce rapprochement quantifie leur influence sans certifier les autres données comme cliniquement valides.

**Priorités proposées :** vérifier les dates après décès ; qualifier les durées extrêmes et leur effet sur la moyenne ; documenter la fin d’observation en février 2022 et les conventions de couverture avant un reporting régulier.

[Qualité · CSV](quality.csv) · [Sensibilité financière · CSV](financial_sensitivity.csv)

## Reproductibilité et vérification

- Archive source inchangée et SHA-256 vérifiés.
- Rapprochement exact des cinq effectifs et des sommes de `TOTAL_CLAIM_COST`, `PAYER_COVERAGE` et `BASE_COST` avec les CSV.
- Huit groupes de tests MySQL : chronologie, bornes de 30 jours, pondération, mois vides, cohortes, dates hors de la vie, médiane et sensibilité aux durées extrêmes.
- Quatre tests Python supplémentaires portent sur l’ancien générateur pédagogique, conservé hors du pipeline de données publié.
- Vérification indépendante en Python des parts, durées et montants du jeu source ; exports agrégés rapprochés du bilan global.
- GitHub Actions exécute l’import Maven, les tests SQL et la comparaison des agrégats versionnés.

[Bilan · CSV](overview.csv) · [Données de la démo · JSON](portfolio.json) · [Version MySQL](environment.tsv)

Les sept TSV conservent les autres analyses SQL. Les retours à 30 jours et les cohortes restent exploratoires, avec des périodes de suivi inégales. Le plan d’exécution est disponible dans [explain.txt](explain.txt), sans revendication de gain de performance non mesuré.
