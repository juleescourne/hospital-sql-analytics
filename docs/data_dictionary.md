# Dictionnaire de données

Le projet s'appuie sur cinq tables relationnelles issues du jeu de données
*Maven Analytics — Hospital Patient Records*. Les types indiqués sont ceux réellement
déclarés dans [`db/schema.sql`](../db/schema.sql).

Les noms de tables et de colonnes restent en anglais : ce sont les identifiants littéraux
du jeu de données source, utilisés tels quels dans les requêtes.

---

## Vue d'ensemble des relations

```text
organizations ──┐
                ├──< encounters ──< procedures
payers ─────────┤        │              │
                │        └──────────────┘
patients ───────┴──< encounters
patients ──────────< procedures
```

Une rencontre (`encounters`) appartient à un patient, se déroule dans une organisation et
est prise en charge par un payeur. Un acte (`procedures`) est rattaché à la fois au patient
et à la rencontre pendant laquelle il a eu lieu.

---

## `patients`

Attributs démographiques, une ligne par patient.

| Colonne | Type | Contrainte | Description |
| --- | --- | --- | --- |
| `Id` | `CHAR(36)` | clé primaire | identifiant du patient (UUID) |
| `BIRTHDATE` | `DATE` | | date de naissance |
| `DEATHDATE` | `DATE` | nullable | date de décès, `NULL` si le patient est vivant |
| `PREFIX`, `FIRST`, `LAST`, `SUFFIX`, `MAIDEN` | `VARCHAR` | | état civil |
| `MARITAL` | `VARCHAR(10)` | | situation maritale |
| `RACE`, `ETHNICITY`, `GENDER` | `VARCHAR` | | champs démographiques |
| `BIRTHPLACE` | `VARCHAR(255)` | | lieu de naissance |
| `ADDRESS`, `CITY`, `STATE`, `COUNTY`, `ZIP` | `VARCHAR` | | adresse |
| `LAT`, `LON` | `DOUBLE` | | coordonnées géographiques |

**Attention à `DEATHDATE`.** C'est le champ le plus piégeux du jeu de données : calculer un
âge avec la date du jour pour un patient décédé produit un âge fictif. Les requêtes du
projet utilisent `LEAST(COALESCE(DEATHDATE, as_of_date), as_of_date)`.

---

## `encounters`

Une ligne par rencontre enregistrée.

| Colonne | Type | Contrainte | Description |
| --- | --- | --- | --- |
| `Id` | `CHAR(36)` | clé primaire | identifiant de la rencontre |
| `START` | `DATETIME` | `NOT NULL` | début |
| `STOP` | `DATETIME` | nullable | fin |
| `PATIENT` | `CHAR(36)` | `NOT NULL`, FK → `patients(Id)` | patient concerné |
| `ORGANIZATION` | `VARCHAR(64)` | `NOT NULL`, FK → `organizations(Id)` | établissement |
| `PAYER` | `CHAR(36)` | nullable, FK → `payers(Id)` | organisme payeur |
| `ENCOUNTERCLASS` | `VARCHAR(50)` | | `ambulatory`, `outpatient`, `emergency`, `inpatient`, `wellness`, `urgentcare` |
| `CODE`, `DESCRIPTION` | `VARCHAR` | | nature de la rencontre |
| `BASE_ENCOUNTER_COST` | `DECIMAL(14,2)` | | coût de base |
| `TOTAL_CLAIM_COST` | `DECIMAL(14,2)` | | montant total facturé |
| `PAYER_COVERAGE` | `DECIMAL(14,2)` | | part prise en charge par le payeur |
| `REASONCODE`, `REASONDESCRIPTION` | `VARCHAR` | nullable | motif, quand il est renseigné |

Le **reste à charge** se calcule par `TOTAL_CLAIM_COST - PAYER_COVERAGE`. Il n'est pas
stocké : le dériver évite qu'il diverge des deux colonnes dont il dépend.

---

## `procedures`

Actes médicaux, rattachés à un patient et à une rencontre.

| Colonne | Type | Contrainte | Description |
| --- | --- | --- | --- |
| `START`, `STOP` | `DATETIME` | | horodatage de l'acte |
| `PATIENT` | `CHAR(36)` | `NOT NULL`, FK → `patients(Id)` | patient |
| `ENCOUNTER` | `CHAR(36)` | `NOT NULL`, FK → `encounters(Id)` | rencontre associée |
| `CODE`, `DESCRIPTION` | `VARCHAR` | | acte réalisé, code et libellé |
| `BASE_COST` | `DECIMAL(14,2)` | | coût de base de l'acte |
| `REASONCODE`, `REASONDESCRIPTION` | `VARCHAR` | nullable | motif, quand il est renseigné |

**Cette table n'a pas de clé primaire.** C'est une caractéristique du jeu source : un même
acte peut légitimement être répété plusieurs fois au cours d'une rencontre, sans identifiant
propre pour les distinguer. Conséquence pratique : un `COUNT(*)` compte des occurrences
d'actes, pas des actes distincts. Les index `idx_procedures_patient`, `idx_procedures_encounter`
et `idx_procedures_start` compensent l'absence de clé pour les jointures et les filtres
temporels.

---

## `payers`

Référentiel des organismes payeurs.

| Colonne | Type | Contrainte | Description |
| --- | --- | --- | --- |
| `Id` | `CHAR(36)` | clé primaire | identifiant du payeur |
| `NAME` | `VARCHAR(100)` | | dénomination |
| `ADDRESS`, `CITY`, `ZIP`, `PHONE` | `VARCHAR` | | coordonnées |
| `STATE_HEADQUARTERED` | `CHAR(2)` | | état du siège social |

`PAYER` est nullable dans `encounters` : une rencontre sans payeur correspond à un patient
non couvert. Toute jointure vers `payers` doit donc être un `LEFT JOIN`, sinon ces
rencontres disparaissent silencieusement des agrégats.

---

## `organizations`

Référentiel des établissements de santé.

| Colonne | Type | Contrainte | Description |
| --- | --- | --- | --- |
| `Id` | `VARCHAR(64)` | clé primaire | identifiant de l'établissement |
| `NAME` | `VARCHAR(255)` | | dénomination |
| `ADDRESS`, `CITY`, `STATE`, `ZIP` | `VARCHAR` | | adresse |

---

## Index déclarés

| Index | Table | Colonnes | Usage |
| --- | --- | --- | --- |
| `idx_encounters_patient_start` | `encounters` | `(PATIENT, START)` | parcours d'un patient dans le temps, fonctions de fenêtrage |
| `idx_encounters_payer` | `encounters` | `(PAYER)` | agrégats par organisme payeur |
| `idx_encounters_class` | `encounters` | `(ENCOUNTERCLASS)` | filtres par type de rencontre |
| `idx_procedures_patient` | `procedures` | `(PATIENT)` | jointure vers `patients` |
| `idx_procedures_encounter` | `procedures` | `(ENCOUNTER)` | jointure vers `encounters` |
| `idx_procedures_start` | `procedures` | `(START)` | filtres et regroupements temporels |

L'index composite `(PATIENT, START)` est celui qui compte : les requêtes de cohorte et de
fenêtrage partitionnent par patient puis ordonnent par date, exactement dans cet ordre.
