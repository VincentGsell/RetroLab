# RetroLab

*Classic Games, Retro Gaming Reimagined*

<p align="center"><img src="docs/img/menu-fr.png" width="560" alt="Le menu de la borne RetroLab : six jeux d'arcade, prêts à jouer"></p>

<details>
<summary><b>🇬🇧 English</b></summary>

Project goals:
- Rewrite and *understand* the emulation of the arcade cabinets and home computers of the era.
- Write it in modern Object Pascal: a faithful abstraction of the game boards and their circuits.
- Rebuild the CPUs and boards of the 1980s chip by chip, as code that both humans and AIs can read and reuse.
- Play my favourite retro games easily, out of the box, with modern gamepads and everything set up properly :)
- Maybe write tribute games to the titles that built the world of video games?

## Play

- Emulated arcade games available: 1942, Commando, Gun.Smoke, 1943 and Ghosts'n Goblins by Capcom, OutRun by Sega.
- With an Xbox gamepad, or any XInput gamepad, plugged in even while the game runs. The keyboard works too.
- Better with two: 1943 is played by two at the same time, in co-op, one gamepad each. 1942, Commando, Gun.Smoke and Ghosts'n Goblins are played by two in turns, as on the cabinet.
- OutRun: left and right steer, button 1 accelerates, button 2 brakes, button 3 shifts gear. The gamepad vibrates when you leave the road; V switches it off.
- F1 shows the controls and lets you change them.

## The project

- This is a work in progress.
- Today, an arcade cabinet emulated in Delphi plays these six games.
- It is deterministic: the same inputs always give the same game. It is the reference for the rewrite.
- What comes next is in the [porting plan](PORTING_PLAN.en.md).

## ROMs: you provide them

No ROM is provided, and none may be added to this repository. Use your own ROM sets, in MAME format, and put them in a `roms/` folder at the root of the repository:

| Game | File | MAME set |
|---|---|---|
| 1942 | `roms/1942.zip` | 1942 (Revision B) |
| Commando | `roms/commando.zip` | Commando (World) |
| Gun.Smoke | `roms/gunsmoke.zip` | Gun.Smoke (World, 1985-11-15) |
| 1943 | `roms/1943.zip` | 1943: The Battle of Midway (Euro) |
| Ghosts'n Goblins | `roms/gng.zip` | Ghosts'n Goblins (World? set 1) |
| OutRun | `roms/outrun.zip` | Out Run (sitdown/upright, Rev B) |

Every file is checked by its CRC32. A wrong or missing file is reported by name.

## Build and run

1. Open `samples/Cabinet/Cabinet.dpr` in Delphi and compile for Win64. Every unit is listed in the `.dpr`: nothing to configure. Developed with Delphi 13.
2. Run `Cabinet.exe`: a menu lists the games, ready or with their ROM missing. `Cabinet.exe --set commando` starts a game directly.

## How the code is organised

The code follows the real machine: a cabinet, boards that plug into it, chips on the boards, and cartridges.

```
samples/Cabinet   the cabinet: window, sound, controls
src/cabinet       monitor, speaker, control panel, gamepads
src/core          the edge connector every board plugs into, ROM loading
src/boards        one unit per hardware board, named after its PCB number
src/chips         processors and sound chips: reusable by any board
src/romsets       the cartridges: which ROM files, for which board
```

### The boards

Each board is a unit (`src/boards/Arcade.Board.<name>.pas`), with its video in `.Video` and sometimes its graphics decoding in `.Gfx`.

| Board | Hardware | Chips on it | Game (cartridge unit) |
|---|---|---|---|
| `Capcom84100` | Capcom PCB 84100, 1984 | 2 × Z80, 2 × AY-3-8910 | 1942 (`Arcade.RomSet.Capcom1942`) |
| `Capcom85605` | Capcom PCB 85605, 1985 | 2 × Z80 (encrypted opcodes), 2 × YM2203 | Commando (`Arcade.RomSet.Commando`) |
| `Capcom85113` | Capcom PCB 85113, 1985 | 2 × Z80, 2 × YM2203 | Gun.Smoke (`Arcade.RomSet.GunSmoke`) |
| `Capcom85606` | Capcom PCB 85606, 1985 | MC6809, Z80, 2 × YM2203 | Ghosts'n Goblins (`Arcade.RomSet.GhostsNGoblins`) |
| `CapcomBM` | Capcom "BM" board, 1987 | 2 × Z80, Intel 8751, 2 × YM2203 | 1943 (`Arcade.RomSet.Midway1943`) |
| `Sega1715376` | Sega 171-5376 (Out Run), 1986 | 2 × MC68000, Z80, YM2151, Sega PCM | OutRun (`Arcade.RomSet.OutRun`) |

### The chips

Each chip is a unit in `src/chips`, with no dependency: it only knows its own pins (memory, interrupts, sound out).

| Chip | Unit | Role | Boards |
|---|---|---|---|
| Zilog Z80 | `Arcade.Chip.Z80` (+ `.Disasm`) | 8-bit CPU, main or sound | all six |
| Motorola MC6809 | `Arcade.Chip.M6809` | 8-bit CPU | Capcom85606 |
| Motorola MC68000 | `Arcade.Chip.M68000` | 16/32-bit CPU | Sega1715376 |
| Intel 8751 (MCS-51) | `Arcade.Chip.MCS51` | protection microcontroller | CapcomBM |
| General Instrument AY-3-8910 | `Arcade.Chip.AY8910` | 3-voice square wave sound | Capcom84100, and inside the YM2203 |
| Yamaha YM2203 | `Arcade.Chip.YM2203` | FM sound, 3 voices | Capcom85605, 85113, 85606, BM |
| Yamaha YM2151 | `Arcade.Chip.YM2151` | FM sound, 8 voices, stereo | Sega1715376 |
| Sega 315-5218 | `Arcade.Chip.SegaPCM` | 16 sampled voices | Sega1715376 |

- A board is named after its hardware (`Capcom84100`), never after a game.
- A game only exists as a cartridge in `src/romsets`.
- Adding a game on known hardware: one cartridge unit.
- Adding hardware: one board unit, reusing the chips.

The programs are in French or English (`--lang fr`, `--lang en`). A translation is one JSON file in `lang/`.

## License

MPL-2.0 ([LICENSE](LICENSE)). Third-party code and trademarks: [NOTICE.md](NOTICE.md). The project uses a few units of the GS-Core library, included in `third_party/gs-core`.

</details>

<details open>
<summary><b>🇫🇷 Français</b></summary>

Buts du projet :
- Réécrire et *comprendre* l'émulation des bornes d'arcade et des ordinateurs de l'époque.
- L'écrire en Pascal objet moderne : une abstraction fidèle des cartes électroniques des jeux et de leurs circuits.
- Reconstruire puce par puce les processeurs et les cartes des années 80, avec un code que les humains comme les IA peuvent lire et réutiliser.
- Jouer facilement à mes jeux rétro préférés, prêts à l'emploi, avec des manettes modernes et tout bien configuré :)
- Peut-être écrire des jeux hommages à ces titres qui ont construit le monde du jeu vidéo ?

## Jouer

- Jeux d'arcade émulés disponibles : 1942, Commando, Gun.Smoke, 1943 et Ghosts'n Goblins de Capcom, OutRun de Sega.
- À la manette Xbox, ou toute manette XInput, branchée même en cours de partie. Le clavier marche aussi.
- À deux, c'est mieux : 1943 se joue à deux en même temps, en coopération, une manette chacun. 1942, Commando, Gun.Smoke et Ghosts'n Goblins se jouent à deux chacun son tour, comme sur la borne.
- OutRun : gauche et droite pour tourner, bouton 1 pour accélérer, bouton 2 pour freiner, bouton 3 pour changer de vitesse. La manette vibre quand on sort de la route ; V coupe les vibrations.
- F1 affiche les commandes et permet de les changer.

## Le projet

- C'est un travail en cours.
- Aujourd'hui, une borne d'arcade émulée en Delphi fait tourner ces six jeux.
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
| Ghosts'n Goblins | `roms/gng.zip` | Ghosts'n Goblins (World? set 1) |
| OutRun | `roms/outrun.zip` | Out Run (sitdown/upright, Rev B) |

Chaque fichier est contrôlé par son CRC32. Un fichier faux ou absent est signalé par son nom.

## Compiler et lancer

1. Ouvrir `samples/Cabinet/Cabinet.dpr` dans Delphi et compiler en Win64. Toutes les unités sont déclarées dans le `.dpr` : rien à configurer. Développé avec Delphi 13.
2. Lancer `Cabinet.exe` : un menu affiche les jeux, prêts ou avec leur ROM manquante. `Cabinet.exe --set commando` lance un jeu directement.

## Organisation du code

Le code suit la vraie machine : une borne, des cartes qui s'y branchent, des puces sur les cartes, et des cartouches.

```
samples/Cabinet   la borne : fenêtre, son, commandes
src/cabinet       écran, haut-parleur, panneau de commandes, manettes
src/core          la prise où se branche chaque carte, chargement des ROM
src/boards        une unité par carte, nommée d'après son numéro de PCB
src/chips         processeurs et puces son : réutilisables par toute carte
src/romsets       les cartouches : quels fichiers ROM, pour quelle carte
```

### Les cartes

Chaque carte est une unité (`src/boards/Arcade.Board.<nom>.pas`), avec sa vidéo dans `.Video` et parfois le décodage de ses graphismes dans `.Gfx`.

| Carte | Matériel | Puces soudées dessus | Jeu (unité de cartouche) |
|---|---|---|---|
| `Capcom84100` | Capcom PCB 84100, 1984 | 2 × Z80, 2 × AY-3-8910 | 1942 (`Arcade.RomSet.Capcom1942`) |
| `Capcom85605` | Capcom PCB 85605, 1985 | 2 × Z80 (opcodes chiffrés), 2 × YM2203 | Commando (`Arcade.RomSet.Commando`) |
| `Capcom85113` | Capcom PCB 85113, 1985 | 2 × Z80, 2 × YM2203 | Gun.Smoke (`Arcade.RomSet.GunSmoke`) |
| `Capcom85606` | Capcom PCB 85606, 1985 | MC6809, Z80, 2 × YM2203 | Ghosts'n Goblins (`Arcade.RomSet.GhostsNGoblins`) |
| `CapcomBM` | carte Capcom « BM », 1987 | 2 × Z80, Intel 8751, 2 × YM2203 | 1943 (`Arcade.RomSet.Midway1943`) |
| `Sega1715376` | Sega 171-5376 (Out Run), 1986 | 2 × MC68000, Z80, YM2151, PCM Sega | OutRun (`Arcade.RomSet.OutRun`) |

### Les puces

Chaque puce est une unité de `src/chips`, sans dépendance : elle ne connaît que ses propres broches (mémoire, interruptions, sortie son).

| Puce | Unité | Rôle | Cartes |
|---|---|---|---|
| Zilog Z80 | `Arcade.Chip.Z80` (+ `.Disasm`) | processeur 8 bits, principal ou son | les six |
| Motorola MC6809 | `Arcade.Chip.M6809` | processeur 8 bits | Capcom85606 |
| Motorola MC68000 | `Arcade.Chip.M68000` | processeur 16/32 bits | Sega1715376 |
| Intel 8751 (MCS-51) | `Arcade.Chip.MCS51` | microcontrôleur de protection | CapcomBM |
| General Instrument AY-3-8910 | `Arcade.Chip.AY8910` | son, 3 voix carrées | Capcom84100, et dans le YM2203 |
| Yamaha YM2203 | `Arcade.Chip.YM2203` | son FM, 3 voix | Capcom85605, 85113, 85606, BM |
| Yamaha YM2151 | `Arcade.Chip.YM2151` | son FM, 8 voix, stéréo | Sega1715376 |
| Sega 315-5218 | `Arcade.Chip.SegaPCM` | 16 voix échantillonnées | Sega1715376 |

- Une carte porte le nom de son matériel (`Capcom84100`), jamais celui d'un jeu.
- Un jeu n'existe que sous forme de cartouche, dans `src/romsets`.
- Ajouter un jeu sur un matériel connu : une unité de cartouche.
- Ajouter un matériel : une unité de carte, qui réutilise les puces.

Les programmes sont en français ou en anglais (`--lang fr`, `--lang en`). Une traduction est un fichier JSON dans `lang/`.

## Licence

MPL-2.0 ([LICENSE](LICENSE)). Code tiers et marques : [NOTICE.md](NOTICE.md). Le projet utilise quelques unités de la bibliothèque GS-Core, incluses dans `third_party/gs-core`.

</details>
