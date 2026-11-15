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
- Emulated cabinet: 1942, Commando, Gun.Smoke, 1943, Ghosts'n Goblins and OutRun.
- Keyboard and gamepad controls, configurable.

Work order:
1. RetroLab Room. It only uses the existing boards and lays the shared FMeX building blocks: up to 4 gamepads, sound, 60 Hz loop, CRT screen.
2. Beloved 43. The simpler remake, built on those blocks.
3. Tribute to Ghosts'n Goblins. Platforming, 4 players and camera: it benefits from Beloved 43.
4. New boards, slotted in as the list of games to cover grows.
5. Commodore 64.

RetroLab Room, the 3D arcade room (`samples/RetroLabRoom`):
- A separate program. Cabinet stays as it is.
- A room with one cabinet per game of the catalog: 1942, Commando, Gun.Smoke, 1943, Ghosts'n Goblins, OutRun.
- ROM present: the cabinet is switched on, in attract mode. Click, play.
- ROM missing: the cabinet is off, and a click says which file to add.
- Each cabinet runs a board of the current cabinet: its picture becomes the screen, its sound a 3D source.
- FMeX rendering, CRT screen effect, cabinets in RetroLab colours (the manufacturers' original artwork is not reproduced).

Beloved 43, a tribute to 1943 in FMeX:
- A game of its own, in the spirit of 1943: vertical shoot'em up, Pacific planes, energy bar, weapon pick-ups, giant bosses.
- New 3D models, levels and music. The music evokes the era without reusing the original melodies. Nothing is taken from the ROM.
- Two-player co-op, no ROM needed: anyone can download it and play.
- The emulated cabinet is the reference for the feel: speed, wave rhythm, difficulty.
- It becomes one more cabinet in RetroLab Room, always switched on.

Tribute to Ghosts'n Goblins, in FMeX (name to be found):
- A game of its own, in the spirit of Ghosts'n Goblins: platforming and shooting, a knight who loses his armour at the first hit, throwing weapons, graveyards and demons.
- Everything is redrawn and the levels are new. Some echo the original ones, so the link is obvious.
- 1 to 4 players at the same time.
- Shared camera that pulls back as players spread out, up to a limit. Beyond it, the player left behind is brought back to the others.
- Difficulty follows the number of players.
- A fallen player can be revived by the others.
- Enemies target the nearest player.
- It also becomes a cabinet in RetroLab Room.

New boards for the cabinet, from closest to what exists to heaviest:

| Game | Hardware | To build | Effort |
|---|---|---|---|
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1: 68000, Z80, YM2151, OKI MSM6295 | MSM6295 chip; CPS-1 video (3 layers, sprites, priorities) | medium, opens the whole CPS-1 library |
| Power Drift (Sega, 1988) | Y Board: 3 × 68000, rotated and zoomed sprites | sprite rotation and zoom | the heaviest |

- The 68000 and the YM2151, written for OutRun, also serve Ghouls'n Ghosts and Power Drift.
- OutRun is played with buttons for now: progressive wheel on left / right, accelerator and brake on buttons 1 and 2, gear on button 3.
- Analog stick and gamepad triggers will come with Power Drift.

Commodore 64:
- Play C64 games with modern gamepads, as with the cabinet: joystick and fire button on the gamepad, joystick 2 for two players.
- Showcase recent C64 games, written and freely released by hobbyists.
- Chips to write: 6510 (a 6502 variant) and its test bench, VIC-II video, SID sound, CIA 6526 (timers, joystick, keyboard).
- Games load from `.prg` files and `.crt` cartridges. The 1541 disk drive comes later, if needed.
- The C64 system ROMs (KERNAL, BASIC, characters) are provided by the user.
