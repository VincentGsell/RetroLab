# Notices

RetroLab (Classic Games, Retro Gaming Reimagined) — Copyright (C) 2026 Vincent Gsell.
Licensed under the Mozilla Public License 2.0 (see [LICENSE](LICENSE)).

## No game data in this repository

This repository contains **no ROM, no graphics, no sound and no code from any Capcom game**.
To run anything, you need ROM sets you are legally entitled to use, placed in `roms/`
(see the README). Every file published here is automatically checked: none of them has the
CRC32 of a ROM declared by the cartridge units.

1942, Commando, Gun.Smoke and 1943 are trademarks of Capcom Co., Ltd. This project is not
affiliated with or endorsed by Capcom.

## Third-party work

| Component | Origin | License |
|---|---|---|
| Board timings, graphics layouts, sprite rendering, ROM set definitions (`src/boards/`, `src/romsets/`) | ported from / generated from the MAME drivers `capcom/1942.cpp`, `1942_v.cpp`, `commando.cpp`, `gunsmoke.cpp`, `1943.cpp` — copyright holders: Paul Leaman, Couriersud, Nicola Salmoria | BSD-3-Clause |
| YM2203 FM model (`src/chips/Arcade.Chip.YM2203.pas`) | follows ymfm — Copyright (c) 2021, Aaron Giles | BSD-3-Clause |
| `third_party/gs-core/` | GS-Core library units by Vincent Gsell (see the README there) | MPL-2.0 (as part of this project) |

BSD-3-Clause notice for the MAME and ymfm derived parts:

> Redistribution and use in source and binary forms, with or without modification, are
> permitted provided that the following conditions are met: (1) Redistributions of source code
> must retain the above copyright notice, this list of conditions and the following disclaimer.
> (2) Redistributions in binary form must reproduce the above copyright notice, this list of
> conditions and the following disclaimer in the documentation and/or other materials provided
> with the distribution. (3) Neither the name of the copyright holder nor the names of its
> contributors may be used to endorse or promote products derived from this software without
> specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
> IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
> FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
> CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
> DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
> DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
> IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
> OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
