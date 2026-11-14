#!/usr/bin/env python3
"""Essai du module 2FujiRaw dans le vrai Lightroom, sans interface, par le pilote du module d'essai de SpektraLR.

    python3 lightroom/tests/essai_lightroom.py <copie d'un .3FR> <dossier des exports>

Le pilote (Photographie/logiciels/spektra-lr/outils/essai-lr) doit être installé et Lightroom ouvert. Une seule
commande, `lua` : tests/essai_lightroom.lua. Les photos d'essai vont dans la collection « 2FujiRaw (essai) - à
retirer » ; les retirer ensuite par l'action `retirer` du pilote (interface libre requise).
Code de sortie 0 si tout ce qui est attendu est constaté.
"""
import hashlib
import json
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
RACINE = ICI.parents[4]  # Développement/
sys.path.insert(0, str(RACINE / 'Photographie/logiciels/spektra-lr/outils/essai-lr'))
import pilote  # noqa: E402

MODULE = Path.home() / 'Library/Application Support/Adobe/Lightroom/Modules/2FujiRaw.lrplugin'
# « Adobe Color » d'abord (référence), un nom inventé (doit retomber sur le défaut), puis les simulations.
PROFILS = ['Adobe Color', 'Camera PROFIL INVENTE', 'Camera PROVIA/Standard', 'Camera Velvia/Vivid',
           'Camera CLASSIC CHROME', 'Camera ACROS']


def lua_chaine(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    source, exports = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    code = (ICI / 'essai_lightroom.lua').read_text(encoding='utf-8')
    code = (code.replace("'%MODULE%'", lua_chaine(MODULE)).replace("'%SOURCE%'", lua_chaine(source))
            .replace("'%EXPORTS%'", lua_chaine(exports))
            .replace('%PROFILS%', '{ ' + ', '.join(lua_chaine(p) for p in PROFILS) + ' }'))
    r = pilote.envoyer({'action': 'lua', 'code': code}, attente=600)
    print(json.dumps(r, ensure_ascii=False, indent=1))
    res = r.get('resultat') or {}
    if not r.get('ok') or res.get('erreur'):
        return 1

    empreintes = {}
    for e in res.get('exports', []):
        if e.get('fichier'):
            empreintes[e['profil']] = hashlib.sha256(Path(e['fichier']).read_bytes()).hexdigest()[:12]
    print('empreintes des exports :', json.dumps(empreintes, ensure_ascii=False, indent=1))
    ref = empreintes.get('Adobe Color')
    controles = {
        'DNG vu comme Fujifilm GFX 100S II': str(res.get('marque')).lower() == 'fujifilm'
        and 'GFX 100S II' in str(res.get('modele')),
        'profil par défaut de Lightroom = simulation Fuji (PROVIA)': res.get('profilParDefaut') == 'Camera PROVIA/Standard',
        'note reprise': res.get('note') == 4,
        'mot-clé repris': 'essai-2fujiraw' in str(res.get('motsCles')),
        'exposition reprise': abs(float(res.get('exposition') or 0) - 0.3) < 1e-6,
        'collection reprise': (res.get('collections') or 0) >= 1,
        'empilé': bool(res.get('enPile')),
        'aucune reprise refusée': not res.get('refus'),
    }
    # Un profil inconnu ne retombe pas sur Adobe Color (constaté le 14/11/2026) : chaque simulation doit donner
    # un rendu à elle, différent d'Adobe Color, du profil inventé et des autres simulations.
    simulations = [empreintes.get(p) for p in PROFILS[2:]]
    autres = {ref, empreintes.get('Camera PROFIL INVENTE')}
    for p in PROFILS[2:]:
        e = empreintes.get(p)
        controles[f'simulation « {p} » reconnue'] = bool(e) and e not in autres and simulations.count(e) == 1
    for nom, ok in controles.items():
        print(('✓ ' if ok else '✗ ') + nom)
    return 0 if all(controles.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
