"""Préparer les CSV publics Maven sans modifier les fichiers source archivés."""
import csv
from datetime import datetime
import hashlib
import io
import json
from pathlib import Path
import zipfile

from generate_sample_data import write_csv, write_loader

ROOT = Path(__file__).resolve().parents[1]
ORDER = ['organizations', 'payers', 'patients', 'encounters', 'procedures']


def read_source():
    source = ROOT / 'data/source'
    manifest = json.loads((source / 'manifest.json').read_text())
    archive = source / 'hospital-patient-records.zip'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['archive_sha256']:
        raise ValueError('Archive source différente du manifeste')
    tables = {}
    with zipfile.ZipFile(archive) as z:
        for name in ORDER:
            filename = name + '.csv'
            raw = z.read(filename)
            if hashlib.sha256(raw).hexdigest() != manifest['files'][filename]['sha256']:
                raise ValueError('Empreinte incorrecte : ' + filename)
            rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'), newline='')))
            if len(rows) != manifest['files'][filename]['rows']:
                raise ValueError('Nombre de lignes incorrect : ' + filename)
            if name != 'procedures' and len({r['Id'] for r in rows}) != len(rows):
                raise ValueError('Identifiant dupliqué : ' + filename)
            tables[name] = rows
    # Vérifier les relations AVANT le chargement (les contraintes SQL ne suffisent
    # pas à prouver qu'aucune ligne n'a été perdue pendant un LOAD DATA LOCAL).
    ids = {name: {r['Id'] for r in tables[name]} for name in ORDER if name != 'procedures'}
    for row in tables['encounters']:
        for field, parent in [('PATIENT', 'patients'), ('ORGANIZATION', 'organizations'), ('PAYER', 'payers')]:
            if row[field] and row[field] not in ids[parent]:
                raise ValueError('Clé orpheline : encounters.' + field)
    for row in tables['procedures']:
        for field, parent in [('PATIENT', 'patients'), ('ENCOUNTER', 'encounters')]:
            if row[field] not in ids[parent]:
                raise ValueError('Clé orpheline : procedures.' + field)
    return tables, manifest


def normalize(tables):
    # Les instants source sont UTC (suffixe Z). MySQL DATETIME conserve ici ces
    # instants en UTC ; pas de conversion vers l'heure locale et pas d'arrondi.
    for name in ['encounters', 'procedures']:
        for row in tables[name]:
            for field in ['START', 'STOP']:
                if row[field]:
                    value = datetime.strptime(row[field], '%Y-%m-%dT%H:%M:%SZ')
                    row[field] = value.strftime('%Y-%m-%d %H:%M:%S')
    return tables


def main():
    tables, _ = read_source()
    normalize(tables)
    out = ROOT / 'data/prepared'
    out.mkdir(parents=True, exist_ok=True)
    for name in ORDER:
        write_csv(tables[name], out / (name + '.csv'))
        print(name, len(tables[name]))
    loader = ROOT / 'db/load_maven.sql'
    write_loader(ORDER, out, loader)
    loader.write_text(loader.read_text().replace(
        '-- Chargement du jeu synthétique généré par scripts/generate_sample_data.py',
        '-- Chargement du jeu public Maven / SyntheticMass, préparé par prepare_maven.py'))


if __name__ == '__main__':
    main()
