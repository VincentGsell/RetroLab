# Porting plan: from the emulated cabinet to a modern native 1942

<p align="center"><a href="PORTING_PLAN.md">🇫🇷 Français</a> &nbsp;|&nbsp; <b>🇬🇧 English</b></p>

## How 1942 is written (1984)

- 72 KB of Z80 assembly, written the old way.
- No OS, no memory allocation, no object tools.
- The whole game state fits in 4 KB of RAM, readable at every frame. This is what makes the reconstruction possible.

| In 1984 | Today |
|---|---|
| Written by hand | current tools and AI assistance |
| Fixed addresses: score, player position, every enemy has its own slot (E000-EFFF) | variables, objects, allocations |
| Slot tables: "enemy #7" = 16 bytes at one address, reused | lists of entities created / destroyed |
| Everything driven by the vblank interrupt (RST 10h) | game loop with a time step |
| State machines encoded as bytes | behaviours, scripts |
| Waves and paths as tables in the ROM banks | level files, editors |
| Integers, fixed point, BCD for the score | floating point |
| Direct writes to video memory / sprite list | renderer receiving a scene |

## The method: the ship of Theseus

The game is replaced plank by plank while it runs.
- The oracle is the emulated cabinet.
- It is deterministic and computes a hash of its state at every frame.
- After each plank is replaced, the hash must stay identical.

1. Understand.
   - Name the RAM by watching what moves (right: player X; enemy shot down: score, slot, explosion).
   - A map of the code already tells which routine writes to which address.
   - A live RAM watcher is still missing.
2. Replace identically.
   - Intercept a Z80 routine at its entry address and run its Pascal version on the same RAM.
   - Replay a game: the hash must stay identical at every frame.
   - Order: BCD score, random and collision, then player, enemies, waves and bosses.
   - End of the step: the main CPU no longer runs any Z80 code.
3. Modernise the code.
   - Raw bytes, then typed structures (`TPlayer`, `TEnemy[n]`, `TWave`), then classes.
   - The oracle then compares the observable state: score, positions, sprites.
4. Separate the rendering.
   - The logic produces a scene: sprites, background, text.
   - Retro renderer identical, pixel for pixel, to the emulator's.
   - Then a modernised FMeX renderer with swappable backgrounds: 1942 has no collision with the ground.
5. Data and sound.
   - Wave and path tables move from the ROM banks to JSON (gs-core), which can be edited.
   - Sound first goes through the AY emulation, driven by the native game.

These steps suit AI tools well: every rewritten routine is checked automatically against the oracle.

Rules:
- Fixed 60 Hz step and integer maths as long as fidelity is the goal.
- Modernising the gameplay comes afterwards, as a deliberate choice.
- Nothing from Capcom is distributed. The native game reads graphics, sounds and tables from the user's own ROM, as the current cartridge loader does.

## Roadmap

Done:
- Emulated cabinet: 1942, Commando, Gun.Smoke and 1943.
- Keyboard and gamepad controls, configurable.

Porting 1942:
1. Record a reference game: `Cabinet.exe --record game1.inp`.
2. Routine interception by address on the Z80, RAM watcher.
3. First native routines: score and random, checked frame by frame.
4. Player, enemies, waves, bosses, until the game is fully native.
5. Modernised code, FMeX renderer, data in JSON.

New boards for the cabinet, from closest to what exists to heaviest:

| Game | Hardware | To build | Effort |
|---|---|---|---|
| Ghosts'n Goblins (Capcom, 1985) | Motorola 6809, Z80 sound, 2 × YM2203 | 6809 chip and its test bench, board, cartridges | medium: YM2203 already there |
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1: 68000, Z80, YM2151, OKI MSM6295 | 68000, YM2151, MSM6295 chips; CPS-1 video (3 layers, sprites, priorities) | large, opens the whole CPS-1 library |
| OutRun (Sega, 1986) | 2 × 68000, Z80, YM2151, SegaPCM, road generator, zoomed sprites | SegaPCM, Sega road and sprite zoom, analog controls | large |
| Power Drift (Sega, 1988) | Y Board: 3 × 68000, rotated and zoomed sprites | sprite rotation and zoom | the heaviest |

- The 68000 and the YM2151 serve Ghouls'n Ghosts, OutRun and Power Drift: each is written once.
- OutRun and Power Drift are played with a wheel: the cabinet will need analog controls.
