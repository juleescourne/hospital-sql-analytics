# Source des données

- Jeu : [Hospital Patient Records — Maven Analytics](https://mavenanalytics.io/data-playground/hospital-patient-records), page consultée le 10 octobre 2026.
- Origine annoncée : SyntheticMass / Synthea ; données synthétiques concernant un établissement du Massachusetts, et non dossiers réels de patients.
- Licence annoncée par Maven : **Public Domain**. Cette indication concerne les données ; le code du projet possède sa propre licence MIT.
- [Synthea explique la nature fictive des données](https://synthetichealth.github.io/about.html).

L’archive `hospital-patient-records.zip` a été créée localement à partir des fichiers fournis pour ce projet. Les octets de chaque CSV, du dictionnaire et de `citation.txt` sont conservés. Il ne s’agit pas d’une copie garantie de l’archive ZIP distribuée par Maven : ses empreintes et sa composition sont propres à ce conditionnement.

Le [manifeste](manifest.json) fournit les tailles, les nombres de lignes et les SHA-256. La préparation vérifie ces empreintes, normalise uniquement le format des horodatages UTC dans des copies, et ne supprime aucune observation. Les fichiers nominatifs contenus dans ce jeu sont synthétiques ; les restitutions du portfolio sont agrégées.

| Table | Lignes |
| --- | ---: |
| patients | 974 |
| encounters | 27 891 |
| procedures | 47 701 |
| payers | 10 |
| organizations | 1 |

La période des débuts de passage va du 2 janvier 2011 au 5 février 2022. Les compteurs affichés sur la page de téléchargement peuvent évoluer ; les volumes de cette étude sont ceux des fichiers vérifiés, pas ceux du catalogue web.

Citation fournie avec les fichiers : Jason Walonoski et al., *Synthea: An approach, method, and software mechanism for generating synthetic patients and the synthetic electronic health care record*, JAMIA, 2018, 25(3), 230–238. https://doi.org/10.1093/jamia/ocx079
