# Résultats exécutés sur données synthétiques

Exécution MySQL 8 dans [GitHub Actions](https://github.com/juleescourne/hospital-sql-analytics/actions/runs/34782086044), graine 42, 400 patients, 7 160 passages et 12 743 actes.
Les fichiers TSV contiennent plusieurs jeux de résultats successifs, chacun avec
son en-tête. Ils sont produits par `bash scripts/run_demo.sh`.

## Contrôle préalable

59 passages sans date de fin, 2 durées négatives et 35 passages sans identifiant
payeur. Aucune relation orpheline ni discordance patient/acte détectée par les
contrôles SQL. Les anomalies temporelles sont injectées par le générateur : les
résultats de durée les excluent, ce qui ramène leur dénominateur à 7 099 passages.
Les montants restent calculés sur les 7 160 passages, dont les montants sont valides.
Les contrôles en base ne remplacent pas une vérification du fichier avant chargement.

## Trois lectures utiles

| Question | Résultat du jeu synthétique | Lecture et action envisageable |
| --- | --- | --- |
| Quels passages mobilisent le plus de temps par événement ? | 207 hospitalisations à durée valide : moyenne 84,33 h ; 3 162 passages ambulatoires : 1,19 h | Distinguer fréquence et durée ; examiner ensuite médiane et dispersion avant une décision de capacité. Ce ne sont pas des heures de travail soignant. |
| Quelle part des coûts est couverte ? | Couverture pondérée globale 65,94 % sur 7 160 passages | Rapport des sommes de couverture et de coût. Contrôler séparément les 35 payeurs inconnus ; une moyenne simple des ratios répondrait à une autre question. |
| Comment l'activité varie-t-elle par année ? | 1 786 passages en 2013, 39 en 2022 | Le générateur et la fenêtre d'observation expliquent cette distribution. On ne peut pas conclure à une chute d'activité d'un établissement réel. |

Le proxy de retour à 30 jours reste une exploration des passages enregistrés ; ce
n'est pas un indicateur clinique de réadmission, ni un résultat de qualité des soins.
Aucune conclusion clinique ou économique réelle ne découle de cet échantillon fictif.

## Plan d'exécution

[explain.txt](explain.txt) montre une lecture de l'index
`idx_encounters_patient_start` **suivie d'un tri**, puis la fonction fenêtre.
L'existence d'un index ne prouve donc pas la suppression du tri. Aucun gain de
performance n'est annoncé sans comparaison mesurée avant/après.
