# Data Dictionary

The project uses five relational tables from the Maven Analytics Hospital Patient Records dataset.

## `patients`

Patient-level demographic attributes.

Key fields:

- `Id` — patient identifier
- `BIRTHDATE`, `DEATHDATE` — lifecycle dates
- `GENDER`, `RACE`, `ETHNICITY`, `MARITAL` — demographic fields
- `CITY`, `STATE`, `COUNTY`, `ZIP` — geographic fields
- `LAT`, `LON` — coordinates

## `encounters`

One row per recorded encounter.

Key fields:

- `Id` — encounter identifier
- `START`, `STOP` — encounter timestamps
- `PATIENT` — foreign key to `patients`
- `ORGANIZATION` — foreign key to `organizations`
- `PAYER` — foreign key to `payers`
- `ENCOUNTERCLASS` — ambulatory, outpatient, emergency, etc.
- `TOTAL_CLAIM_COST` — total claim amount associated with the encounter
- `PAYER_COVERAGE` — amount covered by the payer

## `procedures`

Procedure-level events linked to patients and encounters.

Key fields:

- `PATIENT` — foreign key to `patients`
- `ENCOUNTER` — foreign key to `encounters`
- `START`, `STOP` — procedure timestamps
- `CODE`, `DESCRIPTION` — procedure information
- `BASE_COST` — base procedure cost
- `REASONDESCRIPTION` — reason when available

## `payers`

Insurance / payer reference data.

## `organizations`

Healthcare organization reference data.
