# Lire les analyses

Commencer par `05_data_quality_checks.sql`, puis parcourir `01`, `02`, `03`, `04`, `06` et `07`. Le lanceur conserve cet ordre.

## Qualité et dénominateurs

Les contrôles portent sur la complétude, les intervalles, les montants, les doublons et les relations entre tables. Le contrôle chronologique compare aussi les passages aux dates de naissance et de décès.

Les durées excluent les fins absentes ou antérieures au début. Les durées nulles sont conservées et signalées. Les montants sont disponibles pour tous les passages du jeu synthétique : ils restent dans le calcul des coûts même lorsque la durée est inexploitable. Les motifs de qualité peuvent se chevaucher.

## Activité et parcours

Dans `03`, le passage suivant est déterminé sur tous les débuts enregistrés, ordonnés par `(START, Id)`. On filtre ensuite les passages de référence dont la fin est exploitable. Un retour est compté si `next_start >= STOP` et `next_start <= DATE_ADD(STOP, INTERVAL 30 DAY)`.

La borne vaut exactement 30 × 24 heures, pas 30 jours tronqués à l’entier. Les chevauchements sont exclus. Ce comptage ne définit pas un taux de réadmission : aucune population clinique éligible ni fenêtre complète de suivi n’est construite.

L’âge est calculé à la date de décès lorsqu’elle précède la fin du fichier, sinon à cette fin. Les champs démographiques restent descriptifs.

## Montants et couverture

La couverture globale est `SUM(PAYER_COVERAGE) / SUM(TOTAL_CLAIM_COST)`. Son dénominateur est un montant, pas un nombre de patients. Un payeur non renseigné reste une catégorie distincte : cela ne signifie pas que sa couverture est nulle.

Les coûts des actes dans `04` ne sont pas ajoutés à ceux des passages. Les montants non couverts ne sont pas automatiquement un reste à charge patient.

## Fonctions fenêtres

`06` propose classements, parts, cumul, variation mensuelle, moyenne mobile et cohortes. Le calendrier conserve les mois sans passage : trois lignes représentent trois mois consécutifs. Les deux premiers mois utilisent respectivement une et deux observations. Les mois en dehors des bornes du fichier ne sont pas ajoutés.

Les cohortes sont définies par l’année du premier passage enregistré. Une année observée sans activité vaut zéro ; une année future est absente. Les décès, la couverture inégale et les périodes partielles limitent les comparaisons entre cohortes.

## Synthèse consultable

`07_portfolio_summary.sql` produit quatre jeux de résultats :

1. Volumes, parts de montants, durées moyennes et médianes par classe.
2. Montants couverts et non couverts par payeur.
3. Compteurs de qualité avec leurs dénominateurs.
4. Bilan global de rapprochement.

Les [CSV et leur synthèse](results/README.md) permettent de lire les résultats sans installer MySQL. Les sept TSV regroupent plusieurs tableaux successifs avec leurs en-têtes ; les quatre CSV métier contiennent chacun un seul tableau.

## Contrôles avant publication

`run_demo.sh` exécute quatre tests Python et sept groupes de tests sur les véritables requêtes SQL, puis rapproche les exports métier. Les tests SQL s’exécutent dans des transactions annulées. Consulter `scripts/check_sql.py` pour les petits cas et leurs résultats attendus.
