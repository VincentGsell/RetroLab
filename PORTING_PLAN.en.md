# Roadmap

<p align="center"><a href="PORTING_PLAN.md">🇫🇷 Français</a> &nbsp;|&nbsp; <b>🇬🇧 English</b></p>

## What is done

- The emulated cabinet runs seven games: 1942, Commando, Gun.Smoke, 1943 and Ghosts'n Goblins by Capcom, OutRun and Power Drift by Sega.
- The Z80, MC6809 and MC68000 CPUs are written, and each has its test bench. The AY-3-8910, YM2203 and YM2151 sound chips and Sega's PCM chip are written too.
- You play with the keyboard or a gamepad, and the controls can be configured from the cabinet.
- In OutRun and Power Drift, the gamepad vibrates whenever the original cabinet's wheel did.

## Work order

1. RetroLab Room, the 3D arcade room. It only uses the existing boards, and it lays the FMeX building blocks the remakes will need: up to four gamepads, sound, a 60 Hz loop and a CRT screen rendering.
2. Beloved 43, the simplest of the remakes, built on those blocks.
3. The Ghosts'n Goblins tribute. With platforming, four players and the camera it is the most demanding one, and it will benefit from everything Beloved 43 puts in place.
4. New boards for the cabinet, slotted in as the list of games to cover grows.
5. The Commodore 64.

## RetroLab Room, the 3D arcade room

- It is a separate program (`samples/RetroLabRoom`). The current cabinet, Cabinet, stays as it is.
- The room holds one cabinet per game of the catalog.
- When a game's ROM is present, its cabinet is switched on and runs in attract mode. One click and you play.
- When the ROM is missing, the cabinet is off, and a click tells which file to add.
- Each cabinet runs the same emulated board as Cabinet. Its picture becomes the cabinet screen, and its sound a source placed in the room.
- Rendering uses FMeX, with a CRT screen effect. The cabinets wear RetroLab's colours and do not reproduce the manufacturers' artwork.

## The FMeX remakes

These games are native programs that need no ROM. They pay tribute to the originals with entirely new graphics, levels and music. Each one will become a cabinet in RetroLab Room, always switched on, and the Cabinet menu will show them as "native binary".

### Beloved 43, a tribute to 1943

- It is a vertical shoot'em up in the spirit of 1943, with Pacific planes, an energy bar, weapons to pick up and giant bosses.
- The 3D models, levels and music are new. The music evokes the era without reusing the original melodies.
- Two players play in co-op.
- The emulated cabinet is the reference for the feel of the game: speed, wave rhythm and difficulty.

### Chevalier, the Ghosts'n Goblins tribute (working name)

- It is a platform and shooting game in the spirit of Ghosts'n Goblins: a knight who loses his armour at the first hit, throwing weapons, graveyards and demons.
- Everything is redrawn and the levels are new. Some echo the original ones, so the link with the game is obvious.
- One to four players play at the same time.
- The camera is shared and pulls back as players spread out, up to a limit. Beyond it, the player left behind is brought back to the others.
- Difficulty adapts to the number of players, and a fallen player can be revived by the others.
- Enemies go after the nearest player.

### Power Drift in 3D

- The Power Drift board is emulated. The game will also get an FMeX version, with real 3D tracks.

## Telling how it works

- A detailed, animated presentation of how the emulator works: how a board is rebuilt, how its CPUs advance scanline by scanline, and how the picture is composed layer by layer.
- For each FMeX remake, a detailed description of how it works, in the spirit of Fabien Sanglard's books on the Wolfenstein 3D and Doom engines.
- These descriptions could become an ePub book, readable right inside the game through FMeX.book.

## New boards for the cabinet

| Game | Hardware | What is left to write | Effort |
|---|---|---|---|
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1: 68000, Z80, YM2151, OKI MSM6295 | the MSM6295 chip and the CPS-1 video (three layers, sprites, priorities) | medium, and it opens a large part of the Capcom library |

- The 68000 and the YM2151 were written for OutRun, and the CPS-1 board will reuse them.
- For now OutRun and Power Drift are played with buttons: left and right turn the wheel progressively, buttons 1 and 2 act as accelerator and brake, and button 3 shifts gear. The gamepad's analog stick and triggers are the next step for both games.

## The Commodore 64

- The idea is to play C64 games with modern gamepads, as on the cabinet: the joystick and fire button move to the gamepad, and a second gamepad acts as joystick 2 for two players.
- We also want to give more visibility to recent C64 games, written and freely shared by hobbyists.
- This means writing the 6510 CPU (a 6502 variant) with its test bench, the VIC-II video, the SID sound and the CIA 6526, which handles timers, joystick and keyboard.
- Games will load from `.prg` files and `.crt` cartridges. The 1541 disk drive will come later, if it turns out to be needed.
- The original C64 system ROMs (KERNAL, BASIC and character set) are under a commercial license from Cloanto. Whoever owns them can provide them, as with the arcade games.
- So that people can play right after compiling, without providing anything, we will rely on the Open ROMs from the MEGA65 project, a free (GPL-3.0) rewrite of those ROMs, and on hobbyist games whose authors allow redistribution.
