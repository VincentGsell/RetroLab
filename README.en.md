# RetroLab

*Classic Games, Retro Gaming Reimagined*

<p align="center"><a href="README.md">🇫🇷 Français</a> &nbsp;|&nbsp; <b>🇬🇧 English</b></p>

Rewriting 1980s arcade games in modern Object Pascal, as code that both humans and AIs can read and reuse.

## Play

- Four Capcom arcade games: 1942, Commando, Gun.Smoke and 1943.
- With an Xbox gamepad, or any XInput gamepad, plugged in even while the game runs. The keyboard works too.
- Better with two. 1943 is played by two at the same time, in co-op, one gamepad each. 1942, Commando and Gun.Smoke are played by two in turns, as on the cabinet.
- F1 shows the controls and lets you change them.

## The project

- This is a work in progress.
- Today: an arcade cabinet emulated in Delphi, which plays these four games.
- The emulated cabinet is the reference. It is deterministic: the same inputs always give the same game.
- 1942 is then rewritten one routine at a time, each routine checked against the original, until no emulation is left.
- The next versions are written in modern Pascal, on high-level libraries such as FMeX (rendering, 3D).
- The goal is transferable code: readable, documented, reusable in other projects.

Steps and roadmap: [porting plan](PORTING_PLAN.en.md).

## ROMs: you provide them

No ROM is provided, and none may be added to this repository. Use your own ROM sets, in MAME format, and put them in a `roms/` folder at the root of the repository:

| Game | File | MAME set |
|---|---|---|
| 1942 | `roms/1942.zip` | 1942 (Revision B) |
| Commando | `roms/commando.zip` | Commando (World) |
| Gun.Smoke | `roms/gunsmoke.zip` | Gun.Smoke (World, 1985-11-15) |
| 1943 | `roms/1943.zip` | 1943: The Battle of Midway (Euro) |

Every file is checked by its CRC32. A wrong or missing file is reported by name.

## Build and run

1. Open `samples/Cabinet/Cabinet.dpr` in Delphi and compile for Win64. Every unit is listed in the `.dpr`: nothing to configure. Developed with Delphi 13.
2. Run `Cabinet.exe` for 1942, or `Cabinet.exe --set commando`, `--set gunsmoke`, `--set 1943`.

## How the code is organised

The code follows the real machine: a cabinet, boards that plug into it, chips on the boards, and cartridges.

```
samples/Cabinet   the cabinet: window, sound, controls
src/cabinet       monitor, speaker, control panel, gamepads
src/core          the edge connector every board plugs into, ROM loading
src/boards        one unit per hardware board, named after its PCB number
src/chips         Z80, AY-3-8910, YM2203, Intel 8751: reusable by any board
src/romsets       the cartridges: which ROM files, for which board
```

- A board is named after its hardware (`Capcom84100`), never after a game.
- A game only exists as a cartridge in `src/romsets`.
- Adding a game on known hardware: one cartridge unit.
- Adding hardware: one board unit, reusing the chips.

The programs are in French or English (`--lang fr`, `--lang en`). A translation is one JSON file in `lang/`.

## License

MPL-2.0 ([LICENSE](LICENSE)). Third-party code and trademarks: [NOTICE.md](NOTICE.md). The project uses a few units of the GS-Core library, included in `third_party/gs-core`.
