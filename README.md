# RetroLab

*Classic Games, Retro Gaming Reimagined*

<p align="center"><b>🇫🇷 Français</b> &nbsp;|&nbsp; <a href="README.en.md">🇬🇧 English</a></p>

Réécrire en Pascal objet moderne les jeux d'arcade des années 80, avec un code que les humains comme les IA peuvent lire et réutiliser.

## Jouer

- Quatre jeux d'arcade Capcom : 1942, Commando, Gun.Smoke et 1943.
- À la manette Xbox, ou toute manette XInput, branchée même en cours de partie. Le clavier marche aussi.
- À deux, c'est mieux : 1943 se joue à deux en même temps, en coopération, une manette chacun. 1942, Commando et Gun.Smoke se jouent à deux chacun son tour, comme sur la borne.
- F1 affiche les commandes et permet de les changer.

## Le projet

- C'est un travail en cours.
- Aujourd'hui, une borne d'arcade émulée en Delphi fait tourner ces quatre jeux.
- Elle est déterministe : les mêmes entrées donnent toujours la même partie. Elle sert de référence pour la réécriture.
- La suite est dans le [plan de portage](PORTING_PLAN.md).

## Les ROMs : à fournir vous-même

Aucune ROM n'est fournie, et aucune ne doit être ajoutée à ce dépôt. Utilisez vos propres sets de ROM, au format MAME, dans un dossier `roms/` à la racine du dépôt :

| Jeu | Fichier | Set MAME |
|---|---|---|
| 1942 | `roms/1942.zip` | 1942 (Revision B) |
| Commando | `roms/commando.zip` | Commando (World) |
| Gun.Smoke | `roms/gunsmoke.zip` | Gun.Smoke (World, 1985-11-15) |
| 1943 | `roms/1943.zip` | 1943: The Battle of Midway (Euro) |

Chaque fichier est contrôlé par son CRC32. Un fichier faux ou absent est signalé par son nom.

## Compiler et lancer

1. Ouvrir `samples/Cabinet/Cabinet.dpr` dans Delphi et compiler en Win64. Toutes les unités sont déclarées dans le `.dpr` : rien à configurer. Développé avec Delphi 13.
2. Lancer `Cabinet.exe` pour 1942, ou `Cabinet.exe --set commando`, `--set gunsmoke`, `--set 1943`.

## Organisation du code

Le code suit la vraie machine : une borne, des cartes qui s'y branchent, des puces sur les cartes, et des cartouches.

```
samples/Cabinet   la borne : fenêtre, son, commandes
src/cabinet       écran, haut-parleur, panneau de commandes, manettes
src/core          la prise où se branche chaque carte, chargement des ROM
src/boards        une unité par carte, nommée d'après son numéro de PCB
src/chips         Z80, AY-3-8910, YM2203, Intel 8751 : réutilisables par toute carte
src/romsets       les cartouches : quels fichiers ROM, pour quelle carte
```

- Une carte porte le nom de son matériel (`Capcom84100`), jamais celui d'un jeu.
- Un jeu n'existe que sous forme de cartouche, dans `src/romsets`.
- Ajouter un jeu sur un matériel connu : une unité de cartouche.
- Ajouter un matériel : une unité de carte, qui réutilise les puces.

Les programmes sont en français ou en anglais (`--lang fr`, `--lang en`). Une traduction est un fichier JSON dans `lang/`.

## Licence

MPL-2.0 ([LICENSE](LICENSE)). Code tiers et marques : [NOTICE.md](NOTICE.md). Le projet utilise quelques unités de la bibliothèque GS-Core, incluses dans `third_party/gs-core`.
