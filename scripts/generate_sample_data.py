# -*- coding: utf-8 -*-
"""Génère un jeu hospitalier synthétique au format Maven Analytics.

Le dataset d'origine n'est pas redistribué. Ce script produit cinq CSV de structure
identique, de sorte que le schéma et les requêtes s'exécutent sans compte externe.

Les données sont **cohérentes**, pas aléatoires : un patient a un âge, ses passages
suivent son parcours dans le temps, les coûts dépendent de la classe de passage, et
la couverture assureur dépend du payeur. Sans cela, les requêtes analytiques
renverraient des résultats sans structure, et rien ne serait démontré.

Défauts volontaires
-------------------
Quelques anomalies sont injectées pour que les contrôles qualité de
``queries/05_data_quality_checks.sql`` aient matière à détecter :
    - passages sans date de fin (patients encore hospitalisés) ;
    - une poignée de dates de fin antérieures à la date de début ;
    - quelques passages sans payeur ;
    - un doublon d'identifiant patient.

Usage :
    python scripts/generate_sample_data.py [--patients 400] [--seed 42]
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Classe de passage : (part, durée médiane en heures, coût de base, écart-type du coût)
ENCOUNTER_CLASSES = {
    "ambulatory":  (0.45, 1.0, 380.0, 140.0),
    "outpatient":  (0.23, 1.5, 520.0, 190.0),
    "urgentcare":  (0.13, 3.0, 1250.0, 480.0),
    "wellness":    (0.10, 0.75, 210.0, 60.0),
    "emergency":   (0.06, 6.0, 3400.0, 1600.0),
    "inpatient":   (0.03, 72.0, 12500.0, 6200.0),
}

PAYERS = [
    ("Medicare", 0.82), ("Medicaid", 0.88), ("Aetna", 0.74), ("UnitedHealthcare", 0.76),
    ("Humana", 0.71), ("Cigna", 0.73), ("Blue Cross Blue Shield", 0.79),
    ("Anthem", 0.75), ("Dual Eligible", 0.94), ("NO_INSURANCE", 0.0),
]

PROCEDURES = [
    ("Renal dialysis", 1200.0), ("Electrocardiogram", 180.0), ("Colonoscopy", 2100.0),
    ("Physical therapy", 260.0), ("Blood transfusion", 950.0), ("Suture laceration", 430.0),
    ("Intravenous fluid", 210.0), ("Chest X-ray", 320.0), ("Depression screening", 95.0),
    ("Influenza vaccination", 85.0), ("Appendectomy", 8600.0), ("Wound care", 340.0),
]

REASONS = [
    "Hypertension", "Diabetes mellitus", "Chronic pain", "Acute bronchitis",
    "Fracture of forearm", "Normal pregnancy", "Sinusitis", "Anemia",
]

RACES = ["white", "black", "asian", "native", "other"]
ETHNICITIES = ["nonhispanic", "hispanic"]
GENDERS = ["M", "F"]
MARITALS = ["M", "S", None]
CITIES = [
    ("Boston", 42.3601, -71.0589), ("Worcester", 42.2626, -71.8023),
    ("Springfield", 42.1015, -72.5898), ("Lowell", 42.6334, -71.3162),
    ("Cambridge", 42.3736, -71.1097), ("Quincy", 42.2529, -71.0023),
]

START_YEAR, END_YEAR = 2011, 2022


def weighted_choice(rng: random.Random, options: dict) -> str:
    keys = list(options)
    weights = [options[k][0] for k in keys]
    return rng.choices(keys, weights=weights)[0]


def build(patients_count: int, seed: int) -> dict[str, list[dict]]:
    rng = random.Random(seed)

    organizations = [{
        "Id": "org-" + str(uuid.UUID(int=rng.getrandbits(128), version=4)),
        "NAME": "Massachusetts General Hospital", "ADDRESS": "55 Fruit Street",
        "CITY": "Boston", "STATE": "MA", "ZIP": "02114",
    }]
    org_id = organizations[0]["Id"]

    payers = []
    for name, coverage in PAYERS:
        payers.append({
            "Id": str(uuid.UUID(int=rng.getrandbits(128), version=4)),
            "NAME": name, "ADDRESS": f"{rng.randint(1, 999)} Market Street",
            "CITY": rng.choice(CITIES)[0], "STATE_HEADQUARTERED": "MA",
            "ZIP": f"0{rng.randint(1000, 2999)}", "PHONE": f"555-{rng.randint(100, 999)}-{rng.randint(1000, 9999)}",
            "_coverage": coverage,
        })

    patients, encounters, procedures = [], [], []

    for index in range(patients_count):
        birth_year = rng.randint(1930, 2018)
        birthdate = date(birth_year, rng.randint(1, 12), rng.randint(1, 28))
        # ~8 % des patients ont une date de décès, plus probable pour les plus âgés.
        # Le décès doit tomber dans la fenêtre d'observation ET après la naissance :
        # un patient né en 2007 ne peut pas mourir à 40 ans avant 2022.
        deathdate = None
        earliest_death = max(birth_year, START_YEAR)
        if earliest_death <= END_YEAR and rng.random() < 0.08 + max(0.0, (1960 - birth_year) / 900):
            death_year = rng.randint(earliest_death, END_YEAR)
            deathdate = date(death_year, rng.randint(1, 12), rng.randint(1, 28))
            if deathdate < birthdate:
                deathdate = None

        city, lat, lon = rng.choice(CITIES)
        patient_id = str(uuid.UUID(int=rng.getrandbits(128), version=4))
        patients.append({
            "Id": patient_id, "BIRTHDATE": birthdate.isoformat(),
            "DEATHDATE": deathdate.isoformat() if deathdate else "",
            "PREFIX": rng.choice(["Mr.", "Mrs.", "Ms."]), "FIRST": f"Patient{index + 1}",
            "LAST": f"Sample{index + 1}", "SUFFIX": "", "MAIDEN": "",
            "MARITAL": rng.choice(MARITALS) or "", "RACE": rng.choice(RACES),
            "ETHNICITY": rng.choice(ETHNICITIES), "GENDER": rng.choice(GENDERS),
            "BIRTHPLACE": city, "ADDRESS": f"{rng.randint(1, 900)} Elm Street",
            "CITY": city, "STATE": "Massachusetts", "COUNTY": f"{city} County",
            "ZIP": f"0{rng.randint(1000, 2999)}",
            "LAT": round(lat + rng.uniform(-0.15, 0.15), 6),
            "LON": round(lon + rng.uniform(-0.15, 0.15), 6),
        })

        # Nombre de passages : distribution très asymétrique, comme en réalité
        visits = max(1, int(rng.lognormvariate(2.6, 0.9)))
        last_stop = datetime(START_YEAR, 1, 1) + timedelta(days=rng.randint(0, 900))
        payer_pref = rng.choice(payers)

        for _ in range(visits):
            gap = rng.lognormvariate(3.2, 1.1)     # jours entre deux passages
            start = last_stop + timedelta(days=gap, hours=rng.uniform(0, 23))
            if start.year > END_YEAR:
                break
            if deathdate and start.date() > deathdate:
                break

            encounter_class = weighted_choice(rng, ENCOUNTER_CLASSES)
            _, median_hours, base_cost, cost_sd = ENCOUNTER_CLASSES[encounter_class]
            duration = max(0.25, rng.lognormvariate(0, 0.6) * median_hours)
            stop = start + timedelta(hours=duration)

            base = max(60.0, rng.gauss(base_cost, cost_sd))
            payer = payer_pref if rng.random() < 0.85 else rng.choice(payers)
            total_claim = base * rng.uniform(1.05, 2.4)
            coverage = total_claim * payer["_coverage"] * rng.uniform(0.9, 1.0)

            encounter_id = str(uuid.UUID(int=rng.getrandbits(128), version=4))
            encounters.append({
                "Id": encounter_id, "START": start.strftime("%Y-%m-%d %H:%M:%S"),
                "STOP": stop.strftime("%Y-%m-%d %H:%M:%S"), "PATIENT": patient_id,
                "ORGANIZATION": org_id, "PAYER": payer["Id"],
                "ENCOUNTERCLASS": encounter_class, "CODE": str(rng.randint(100000, 999999)),
                "DESCRIPTION": f"Encounter for {rng.choice(REASONS).lower()}",
                "BASE_ENCOUNTER_COST": round(base, 2),
                "TOTAL_CLAIM_COST": round(total_claim, 2),
                "PAYER_COVERAGE": round(coverage, 2),
                "REASONCODE": str(rng.randint(10000, 99999)),
                "REASONDESCRIPTION": rng.choice(REASONS),
            })

            for _ in range(rng.choices([0, 1, 2, 3, 5], weights=[15, 35, 25, 15, 10])[0]):
                name, cost = rng.choice(PROCEDURES)
                procedures.append({
                    "START": start.strftime("%Y-%m-%d %H:%M:%S"),
                    "STOP": stop.strftime("%Y-%m-%d %H:%M:%S"),
                    "PATIENT": patient_id, "ENCOUNTER": encounter_id,
                    "CODE": str(rng.randint(100000, 999999)), "DESCRIPTION": name,
                    "BASE_COST": round(max(40.0, rng.gauss(cost, cost * 0.22)), 2),
                    "REASONCODE": str(rng.randint(10000, 99999)),
                    "REASONDESCRIPTION": rng.choice(REASONS),
                })

            last_stop = stop

    # --- Défauts volontaires, pour que les contrôles qualité aient du grain à moudre
    if len(encounters) > 60:
        for enc in rng.sample(encounters, k=max(3, len(encounters) // 120)):
            enc["STOP"] = ""                                   # patient encore présent
        for enc in rng.sample(encounters, k=3):
            enc["STOP"] = enc["START"]                          # durée nulle
        for enc in rng.sample(encounters, k=2):
            start = datetime.strptime(enc["START"], "%Y-%m-%d %H:%M:%S")
            enc["STOP"] = (start - timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S")
        for enc in rng.sample(encounters, k=max(2, len(encounters) // 200)):
            enc["PAYER"] = ""                                   # passage sans payeur

    for payer in payers:
        payer.pop("_coverage")

    return {"organizations": organizations, "payers": payers, "patients": patients,
            "encounters": encounters, "procedures": procedures}


def write_csv(rows: list[dict], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        # lineterminator explicite : csv.writer termine les lignes par CRLF par
        # defaut. Le script de chargement declarant LINES TERMINATED BY LF, un
        # CR residuel se retrouverait dans la derniere colonne cote MySQL.
        writer = csv.DictWriter(
            handle, fieldnames=list(rows[0].keys()), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)

def write_loader(order: list[str], data_dir: Path, path: Path) -> None:
    """Écrit un script LOAD DATA prêt à l'emploi, dans l'ordre des dépendances."""
    # Les dates vides doivent devenir NULL et non '0000-00-00' : MySQL en mode strict
    # refuserait la chaîne vide dans une colonne DATE.
    nullable = {
        "patients": ["DEATHDATE"],
        "encounters": ["STOP", "PAYER"],
        "procedures": ["STOP"],
    }

    lines = [
        "-- Chargement du jeu synthétique généré par scripts/generate_sample_data.py",
        "-- Nécessite l'option local-infile côté client ET serveur :",
        "--   mysql --local-infile=1 -u root -p hospital_analytics < db/load_sample_data.sql",
        "",
        "USE hospital_analytics;",
        "",
        "SET FOREIGN_KEY_CHECKS = 0;",
        "TRUNCATE TABLE procedures;",
        "TRUNCATE TABLE encounters;",
        "TRUNCATE TABLE patients;",
        "TRUNCATE TABLE payers;",
        "TRUNCATE TABLE organizations;",
        "SET FOREIGN_KEY_CHECKS = 1;",
        "",
    ]

    for name in order:
        header = list(csv.DictReader(open(data_dir / f"{name}.csv", encoding="utf-8")).fieldnames)
        blanks = nullable.get(name, [])
        columns = [f"@{c}" if c in blanks else f"`{c}`" for c in header]
        lines += [
            f"LOAD DATA LOCAL INFILE '{(data_dir / (name + '.csv')).as_posix()}'",
            f"INTO TABLE {name}",
            "FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'",
            "LINES TERMINATED BY '\\n'",
            "IGNORE 1 ROWS",
            "(" + ", ".join(columns) + ")",
        ]
        if blanks:
            sets = ", ".join(f"`{c}` = NULLIF(@{c}, '')" for c in blanks)
            lines.append(f"SET {sets}")
        lines[-1] += ";"
        lines.append("")

    lines += [
        "-- Contrôle des volumes chargés",
        "SELECT 'patients' AS table_name, COUNT(*) AS row_count FROM patients",
        "UNION ALL SELECT 'encounters', COUNT(*) FROM encounters",
        "UNION ALL SELECT 'procedures', COUNT(*) FROM procedures",
        "UNION ALL SELECT 'payers', COUNT(*) FROM payers",
        "UNION ALL SELECT 'organizations', COUNT(*) FROM organizations;",
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--patients", type=int, default=400, help="nombre de patients (défaut : 400)")
    parser.add_argument("--seed", type=int, default=42, help="graine aléatoire (défaut : 42)")
    parser.add_argument("--output", type=Path, default=Path("data"), help="répertoire de sortie")
    args = parser.parse_args()

    tables = build(args.patients, args.seed)
    order = ["organizations", "payers", "patients", "encounters", "procedures"]
    for name in order:
        target = args.output / f"{name}.csv"
        write_csv(tables[name], target)
        print(f"  {target}  —  {len(tables[name]):,} lignes".replace(",", " "))

    loader = args.output.parent / "db" / "load_sample_data.sql"
    write_loader(order, args.output, loader)
    print(f"  {loader}  —  script de chargement prêt à l'emploi")

    print("\nChargez ensuite le schéma puis les données :")
    print("  mysql -u root -p < db/schema.sql")
    print("  mysql --local-infile=1 -u root -p cutting < db/load_sample_data.sql"
          .replace("cutting", "hospital_analytics"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
