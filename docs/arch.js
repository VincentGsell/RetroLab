// RetroLab : boards and chips explorer. The data follows the unit headers in src/boards and src/chips.
(function () {
  var lang = document.documentElement.lang === 'fr' ? 'fr' : 'en';
  function t(o) { return typeof o === 'string' ? o : o[lang]; }

  var L = {
    hardware: { fr: 'Matériel', en: 'Hardware' },
    chips: { fr: 'Puces soudées dessus', en: 'Chips on it' },
    video: { fr: 'Vidéo', en: 'Video' },
    more: { fr: 'À noter', en: 'Worth knowing' },
    units: { fr: 'Unités', en: 'Units' },
    game: { fr: 'Jeu (cartouche)', en: 'Game (cartridge)' },
    ref: { fr: 'Référence MAME', en: 'MAME reference' },
    role: { fr: 'Ce qui est émulé', en: 'What is emulated' },
    check: { fr: 'Vérification', en: 'How it is checked' },
    used: { fr: 'Sur les cartes', en: 'On the boards' },
    pick: { fr: 'Choisissez une carte ou une puce.', en: 'Pick a board or a chip.' }
  };

  var chips = [
    { id: 'z80', name: 'Zilog Z80', unit: 'Arcade.Chip.Z80, Arcade.Chip.Z80.Disasm',
      kind: { fr: 'processeur 8 bits', en: '8-bit CPU' },
      role: { fr: 'Jeu d\'instructions complet, opcodes et comportements non documentés compris : registres IXH/IXL, SLL, drapeaux X et Y, fuite du registre interne MEMPTR dans BIT n,(HL). Durée exacte de chaque instruction. Un désassembleur partage le même décodage.',
              en: 'Full instruction set, undocumented opcodes and behaviour included: IXH/IXL registers, SLL, X and Y flags, the internal MEMPTR register leaking into BIT n,(HL). Exact duration of every instruction. A disassembler shares the same decoding.' },
      check: { fr: 'ZEXDOC et ZEXALL, les suites de référence du Z80 : 67 tests sur 67.', en: 'ZEXDOC and ZEXALL, the Z80 reference suites: 67 tests out of 67.' } },
    { id: 'm6809', name: 'Motorola MC6809', unit: 'Arcade.Chip.M6809',
      kind: { fr: 'processeur 8 bits', en: '8-bit CPU' },
      role: { fr: 'Jeu complet (pages 0, 2 et 3), tous les modes indexés, interruptions IRQ, FIRQ et NMI, SWI 1 à 3, CWAI, SYNC. Cycles d\'après la fiche Motorola, modes indexés compris.',
              en: 'Full set (pages 0, 2 and 3), every indexed mode, IRQ, FIRQ and NMI interrupts, SWI 1 to 3, CWAI, SYNC. Cycle counts from the Motorola datasheet, indexed modes included.' },
      check: { fr: 'Programme de test assemblé à la main : 15 contrôles sur 15. Puis le test de démarrage de Ghosts\'n Goblins (RAM OK, ROM CHECK).', en: 'Hand-assembled test program: 15 checks out of 15. Then the Ghosts\'n Goblins boot test (RAM OK, ROM CHECK).' } },
    { id: 'm68000', name: 'Motorola MC68000', unit: 'Arcade.Chip.M68000',
      kind: { fr: 'processeur 16/32 bits', en: '16/32-bit CPU' },
      role: { fr: 'Jeu complet, tous les modes d\'adressage, piles superviseur et utilisateur, interruptions autovectorisées sur 7 niveaux, trace, STOP. Cycles d\'après le manuel Motorola, y compris MULU, MULS, DIVU et DIVS dont la durée dépend des données.',
              en: 'Full set, every addressing mode, supervisor and user stacks, autovectored interrupts on 7 levels, trace, STOP. Cycle counts from the Motorola manual, including MULU, MULS, DIVU and DIVS whose duration depends on the data.' },
      check: { fr: 'Suite SingleStepTests : 99,55 % de 822 000 instructions identiques à la vraie puce (registres, mémoire, nombre de cycles). Les erreurs d\'adresse, qu\'aucun jeu n\'utilise, ne sont pas émulées.',
               en: 'SingleStepTests suite: 99.55 % of 822,000 instructions identical to the real chip (registers, memory, cycle count). Address errors, which no game uses, are not emulated.' } },
    { id: 'mcs51', name: 'Intel 8751 (MCS-51)', unit: 'Arcade.Chip.MCS51',
      kind: { fr: 'microcontrôleur', en: 'microcontroller' },
      role: { fr: '4 Ko de ROM interne, 128 octets de RAM, 4 ports, 2 timers, 5 interruptions sur 2 niveaux. Comme sur la vraie puce, une lecture simple lit les broches, une instruction lecture-modification-écriture lit le verrou du port.',
              en: '4 KB of internal ROM, 128 bytes of RAM, 4 ports, 2 timers, 5 interrupts on 2 levels. As on the real chip, a plain read reads the pins, a read-modify-write instruction reads the port latch.' },
      check: { fr: 'En jeu : il fait tourner le programme de protection de 1943, qui échange des octets avec les deux Z80.', en: 'In game: it runs the 1943 protection program, which swaps bytes with both Z80s.' } },
    { id: 'ay8910', name: 'General Instrument AY-3-8910', unit: 'Arcade.Chip.AY8910',
      kind: { fr: 'son', en: 'sound' },
      role: { fr: '3 voix carrées, un générateur de bruit, une enveloppe. Calculé à l\'horloge de la puce divisée par 8, puis filtré vers la fréquence de sortie : pas de sifflement d\'aliasing.',
              en: '3 square voices, a noise generator, an envelope. Computed at the chip clock divided by 8, then filtered down to the output rate: no aliasing whine.' },
      check: { fr: 'Les musiques de 1942, et la partie SSG intégrée au YM2203.', en: 'The 1942 music, and the SSG part built into the YM2203.' } },
    { id: 'ym2203', name: 'Yamaha YM2203', unit: 'Arcade.Chip.YM2203',
      kind: { fr: 'son FM', en: 'FM sound' },
      role: { fr: 'FM à 4 opérateurs, 3 voix, 8 algorithmes, plus un AY-3-8910 intégré et 2 timers. Modèle d\'après ymfm, le cœur Yamaha de MAME, issu de l\'étude du silicium.',
              en: '4-operator FM, 3 voices, 8 algorithms, plus a built-in AY-3-8910 and 2 timers. Model after ymfm, MAME\'s Yamaha core, built from die-level research.' },
      check: { fr: 'Banc de test rendu en WAV, comparé au spectre.', en: 'Test bench rendered to WAV, compared by spectrum.' } },
    { id: 'ym2151', name: 'Yamaha YM2151', unit: 'Arcade.Chip.YM2151',
      kind: { fr: 'son FM stéréo', en: 'stereo FM sound' },
      role: { fr: '8 voix FM stéréo, LFO à 4 formes d\'onde, bruit, 2 timers, convertisseur YM3012 avec sa troncature en virgule flottante. Table de hauteur des notes relevée sur la puce (David Viens), via ymfm.',
              en: '8 stereo FM voices, LFO with 4 waveforms, noise, 2 timers, YM3012 converter with its floating-point truncation. Note pitch table measured on the chip (David Viens), via ymfm.' },
      check: { fr: 'Les musiques d\'OutRun et de Power Drift.', en: 'The music of OutRun and Power Drift.' } },
    { id: 'segamath', name: 'Sega 315-5248 / 315-5249', unit: 'Arcade.Chip.SegaMath',
      kind: { fr: 'calcul câblé', en: 'hardware arithmetic' },
      role: { fr: 'Le multiplicateur rend le produit signé de deux nombres de 16 bits. Le diviseur divise un nombre de 32 bits par un nombre de 16 bits, en signé avec quotient borné et reste, ou en non signé avec un quotient de 32 bits, et signale la division par zéro et le débordement.',
              en: 'The multiplier returns the signed product of two 16-bit numbers. The divider divides a 32-bit number by a 16-bit one, signed with a clamped quotient and a remainder, or unsigned with a 32-bit quotient, and flags division by zero and overflow.' },
      check: { fr: 'En jeu : chaque 68000 de Power Drift a sa paire, et toute la 3D du jeu passe par elles.', en: 'In game: each Power Drift 68000 has its pair, and all the game\'s 3D goes through them.' } },
    { id: 'sega5296', name: 'Sega 315-5296', unit: 'Arcade.Chip.Sega315_5296',
      kind: { fr: 'entrées-sorties', en: 'I/O' },
      role: { fr: '8 ports, chacun en entrée ou en sortie : boutons, monnayeur, DIP, moteurs, et le reset des processeurs secondaires. Il répond aussi « SEGA » sur 4 registres, que le jeu vérifie.',
              en: '8 ports, each one an input or an output: buttons, coin slots, DIP switches, motors, and the reset of the secondary CPUs. It also answers "SEGA" on 4 registers, which the game checks.' },
      check: { fr: 'En jeu : Power Drift démarre, lit ses commandes et pilote ses sorties.', en: 'In game: Power Drift boots, reads its controls and drives its outputs.' } },
    { id: 'segapcm', name: 'Sega 315-5218', unit: 'Arcade.Chip.SegaPCM',
      kind: { fr: 'son échantillonné', en: 'sampled sound' },
      role: { fr: '16 voix d\'échantillons 8 bits lus en ROM, volume gauche et droite, boucles, banques de ROM.',
              en: '16 voices of 8-bit samples read from ROM, left and right volume, loops, ROM banks.' },
      check: { fr: 'Les voix et bruitages d\'OutRun et de Power Drift.', en: 'The voices and sound effects of OutRun and Power Drift.' } }
  ];

  var boards = [
    { id: 'capcom84100', name: 'Capcom84100', game: '1942', year: 1984,
      hw: { fr: 'Capcom PCB 84100 (deux cartes empilées), quartz 12 MHz, écran vertical 256 × 224 à 59,64 Hz.', en: 'Capcom PCB 84100 (two stacked boards), 12 MHz crystal, vertical 256 × 224 screen at 59.64 Hz.' },
      chips: [['z80', 2], ['ay8910', 2]],
      clocks: { fr: 'Z80 principal 3 MHz, Z80 son 3 MHz, 2 × AY-3-8910 à 1,5 MHz.', en: 'Main Z80 3 MHz, sound Z80 3 MHz, 2 × AY-3-8910 at 1.5 MHz.' },
      video: { fr: 'Décor de tuiles 16 × 16 qui défile, 32 sprites, texte 8 × 8, palette en PROM.', en: 'Scrolling 16 × 16 tile background, 32 sprites, 8 × 8 text layer, PROM palette.' },
      more: { fr: 'Les interruptions viennent d\'une PROM lue à chaque ligne d\'écran.', en: 'Interrupts come from a PROM read at every scanline.' },
      units: 'Arcade.Board.Capcom84100, .Video, .Gfx', cart: 'Arcade.RomSet.Capcom1942', ref: 'capcom/1942.cpp' },
    { id: 'capcom85605', name: 'Capcom85605', game: 'Commando', year: 1985,
      hw: { fr: 'Capcom PCB 85605 (trois cartes), descendante directe de la 84100 : même PROM d\'interruptions, mêmes formats graphiques.', en: 'Capcom PCB 85605 (three boards), a direct descendant of the 84100: same interrupt PROM, same graphics formats.' },
      chips: [['z80', 2], ['ym2203', 2]],
      clocks: { fr: 'Z80 principal 3 MHz, Z80 son 3 MHz, 2 × YM2203 à 1,5 MHz.', en: 'Main Z80 3 MHz, sound Z80 3 MHz, 2 × YM2203 at 1.5 MHz.' },
      video: { fr: 'Décor 512 × 512 qui défile sur les deux axes, 96 sprites copiés par DMA, texte 8 × 8, palette RGB 4 bits.', en: '512 × 512 background scrolling on both axes, 96 sprites copied by DMA, 8 × 8 text layer, 4-bit RGB palette.' },
      more: { fr: 'Les instructions du processeur principal sont chiffrées, pas ses données : le déchiffrement se fait à la lecture des opcodes.', en: 'The main CPU\'s instructions are encrypted, not its data: decryption happens on opcode fetches.' },
      units: 'Arcade.Board.Capcom85605, .Video', cart: 'Arcade.RomSet.Commando', ref: 'capcom/commando.cpp' },
    { id: 'capcom85113', name: 'Capcom85113', game: 'Gun.Smoke', year: 1985,
      hw: { fr: 'Capcom PCB 85113, quartz 12 MHz. Programme du processeur principal en 4 banques de 16 Ko.', en: 'Capcom PCB 85113, 12 MHz crystal. Main CPU program in 4 banks of 16 KB.' },
      chips: [['z80', 2], ['ym2203', 2]],
      clocks: { fr: 'Z80 principal 3 MHz, Z80 son 3 MHz (dans un circuit Capcom 85H001), 2 × YM2203 à 1,5 MHz.', en: 'Main Z80 3 MHz, sound Z80 3 MHz (inside a Capcom 85H001 custom), 2 × YM2203 at 1.5 MHz.' },
      video: { fr: 'Décor lu directement en ROM (une carte de 2048 × 8 tuiles de 32 × 32), 128 sprites, texte. Chaque plan s\'allume ou s\'éteint sur ordre du jeu.', en: 'Background read straight from ROM (a 2048 × 8 map of 32 × 32 tiles), 128 sprites, text layer. The game switches each layer on or off.' },
      more: { fr: '3 boutons de tir par joueur : à gauche, au centre, à droite.', en: '3 fire buttons per player: left, centre, right.' },
      units: 'Arcade.Board.Capcom85113, .Video, .Gfx', cart: 'Arcade.RomSet.GunSmoke', ref: 'capcom/gunsmoke.cpp' },
    { id: 'capcom85606', name: 'Capcom85606', game: 'Ghosts\'n Goblins', year: 1985,
      hw: { fr: 'Capcom PCB 85606 (carte processeur et son, carte vidéo), quartz 12 MHz. Banques de ROM pour le programme principal.', en: 'Capcom PCB 85606 (CPU and sound board, video board), 12 MHz crystal. ROM banks for the main program.' },
      chips: [['m6809', 1], ['z80', 1], ['ym2203', 2]],
      clocks: { fr: 'MC6809 1,5 MHz (horloge E), Z80 son 3 MHz, 2 × YM2203 à 1,5 MHz.', en: 'MC6809 1.5 MHz (E clock), sound Z80 3 MHz, 2 × YM2203 at 1.5 MHz.' },
      video: { fr: 'Décor 512 × 512 sur deux niveaux : certaines tuiles passent devant les sprites. 128 sprites copiés dans un tampon, texte, palette RGB 4 bits écrite par le jeu.', en: '512 × 512 background on two levels: some tiles pass in front of the sprites. 128 sprites copied into a buffer, text layer, 4-bit RGB palette written by the game.' },
      more: { fr: 'Un verrou 74LS259 retourne l\'écran et tient le processeur son en reset.', en: 'A 74LS259 latch flips the screen and holds the sound CPU in reset.' },
      units: 'Arcade.Board.Capcom85606, .Video', cart: 'Arcade.RomSet.GhostsNGoblins', ref: 'capcom/gng.cpp' },
    { id: 'sega1715376', name: 'Sega1715376', game: 'OutRun', year: 1986,
      hw: { fr: 'Carte processeur Sega 171-5376 et carte vidéo 837-6064. Écran horizontal 320 × 224 à 60,05 Hz.', en: 'Sega 171-5376 CPU board and 837-6064 video board. Horizontal 320 × 224 screen at 60.05 Hz.' },
      chips: [['m68000', 2], ['z80', 1], ['ym2151', 1], ['segapcm', 1]],
      clocks: { fr: '2 × MC68000 à 10 MHz (jeu et route), Z80 son 4 MHz, YM2151 et PCM à 4 MHz.', en: '2 × MC68000 at 10 MHz (game and road), sound Z80 4 MHz, YM2151 and PCM at 4 MHz.' },
      video: { fr: 'Plans de tuiles System 16B (2 couches sur 16 pages, plus le texte), générateur de route (2 routes mélangées par une PAL), sprites zoomés en double tampon, 4096 couleurs avec ombre et surbrillance.', en: 'System 16B tilemaps (2 layers over 16 pages, plus text), road generator (2 roads mixed by a PAL), zoomed sprites in a double buffer, 4096 colours with shadow and hilight.' },
      more: { fr: 'Le contrôleur mémoire 315-5195 place l\'espace du processeur principal en 8 régions programmables. Volant et pédales passent par un convertisseur ADC0804 ; le vibreur du volant fait vibrer la manette.', en: 'The 315-5195 memory mapper places the main CPU\'s space in 8 programmable regions. Wheel and pedals go through an ADC0804 converter; the wheel shaker drives the gamepad rumble.' },
      units: 'Arcade.Board.Sega1715376, .Video', cart: 'Arcade.RomSet.OutRun', ref: 'sega/segaorun.cpp' },
    { id: 'capcombm', name: 'CapcomBM', game: '1943', year: 1987,
      hw: { fr: 'Carte Capcom « BM » (le code imprimé sur toutes ses ROM), quartz 24 MHz, issue de la 85113. Programme principal en 8 banques de 16 Ko.', en: 'Capcom "BM" board (the code printed on all its ROMs), 24 MHz crystal, grown from the 85113. Main program in 8 banks of 16 KB.' },
      chips: [['z80', 2], ['mcs51', 1], ['ym2203', 2]],
      clocks: { fr: 'Z80 principal 6 MHz, Z80 son 3 MHz, Intel 8751 à 3 MHz, 2 × YM2203 à 1,5 MHz.', en: 'Main Z80 6 MHz, sound Z80 3 MHz, Intel 8751 at 3 MHz, 2 × YM2203 at 1.5 MHz.' },
      video: { fr: 'Deux décors lus en ROM, 128 sprites avec priorité pixel par pixel sur le décor de devant, texte ; chaque plan s\'allume ou s\'éteint.', en: 'Two backgrounds read from ROM, 128 sprites with per-pixel priority against the front background, text layer; each layer can be switched off.' },
      more: { fr: 'Le 8751 est le microcontrôleur de protection : il échange des octets avec le processeur principal et le processeur son, et lit la ligne d\'écran en cours.', en: 'The 8751 is the protection microcontroller: it swaps bytes with the main and sound CPUs, and reads the current scanline.' },
      units: 'Arcade.Board.CapcomBM, .Video, .Gfx', cart: 'Arcade.RomSet.Midway1943', ref: 'capcom/1943.cpp' },
    { id: 'sega1715609', name: 'Sega1715609', game: 'Power Drift', year: 1988,
      hw: { fr: 'Sega Y Board : carte du dessus 171-5609 et carte du dessous 171-5610. Écran horizontal 320 × 224 à 60 Hz.', en: 'Sega Y Board: top board 171-5609 and bottom board 171-5610. Horizontal 320 × 224 screen at 60 Hz.' },
      chips: [['m68000', 3], ['z80', 1], ['ym2151', 1], ['segapcm', 1], ['segamath', 3], ['sega5296', 1]],
      clocks: { fr: '3 × MC68000 à 12,5 MHz (le jeu, les sprites tournés, la rotation et l\'affichage), Z80 son, YM2151 et PCM à 4 MHz.', en: '3 × MC68000 at 12.5 MHz (the game, the rotated sprites, rotation and display), sound Z80, YM2151 and PCM at 4 MHz.' },
      video: { fr: 'Les sprites Y Board sont dessinés dans une image de 512 × 512, que la puce de rotation lit à travers une transformation affine : toute la scène tourne et s\'incline. Un second jeu de sprites System 16B passe par-dessus, avec priorité et ombre. Palette de 8192 couleurs.', en: 'The Y Board sprites are drawn into a 512 × 512 picture, which the rotation chip reads through an affine transform: the whole scene turns and tilts. A second System 16B sprite set goes on top, with priority and shadow. 8192-colour palette.' },
      more: { fr: 'Le Z80 son reçoit une NMI à chaque commande et l\'IRQ du YM2151. Volant et pédales passent par un convertisseur MSM6253 qui rend son résultat bit par bit.', en: 'The sound Z80 gets an NMI on each command and the YM2151 IRQ. Wheel and pedals go through an MSM6253 converter that returns its result bit by bit.' },
      units: 'Arcade.Board.Sega1715609, .Video, Arcade.Board.SegaPalette', cart: 'Arcade.RomSet.PowerDrift', ref: 'sega/segaybd.cpp' }
  ];

  var root = document.getElementById('explorer');
  if (!root) return;
  var boardList = root.querySelector('.boards');
  var chipList = root.querySelector('.chips');
  var detail = root.querySelector('.detail');
  var items = {};

  function chipName(id) { for (var i = 0; i < chips.length; i++) if (chips[i].id === id) return chips[i].name; return id; }
  function boardsOf(id) { return boards.filter(function (b) { return b.chips.some(function (c) { return c[0] === id; }); }); }

  function add(list, key, title, sub) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'item';
    b.innerHTML = '<span class="name"></span><span class="sub"></span>';
    b.querySelector('.name').textContent = title;
    b.querySelector('.sub').textContent = sub;
    b.addEventListener('click', function () { select(key); });
    list.appendChild(b);
    items[key] = b;
  }

  boards.forEach(function (b) { add(boardList, 'b:' + b.id, b.name, b.game + ' · ' + b.year); });
  chips.forEach(function (c) { add(chipList, 'c:' + c.id, c.name, t(c.kind)); });

  function row(label, html) { return '<dt>' + t(L[label]) + '</dt><dd>' + html + '</dd>'; }
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  function code(s) { return s.split(', ').map(function (u) { return '<code>' + esc(u) + '</code>'; }).join(' '); }

  function select(key) {
    var linked = {};
    var html = '';
    if (key.indexOf('b:') === 0) {
      var b = boards.filter(function (x) { return 'b:' + x.id === key; })[0];
      b.chips.forEach(function (c) { linked['c:' + c[0]] = true; });
      html = '<h3>' + esc(b.name) + '</h3><dl>' +
        row('hardware', esc(t(b.hw))) +
        row('chips', b.chips.map(function (c) { return (c[1] > 1 ? c[1] + ' × ' : '') + esc(chipName(c[0])); }).join(', ') + '<br>' + esc(t(b.clocks))) +
        row('video', esc(t(b.video))) +
        row('more', esc(t(b.more))) +
        row('units', code(b.units)) +
        row('game', esc(b.game) + ' : ' + code(b.cart)) +
        row('ref', '<code>' + esc(b.ref) + '</code>') + '</dl>';
    } else {
      var c = chips.filter(function (x) { return 'c:' + x.id === key; })[0];
      boardsOf(c.id).forEach(function (b) { linked['b:' + b.id] = true; });
      html = '<h3>' + esc(c.name) + '</h3><dl>' +
        row('role', esc(t(c.role))) +
        row('check', esc(t(c.check))) +
        row('units', code(c.unit)) +
        row('used', boardsOf(c.id).map(function (b) { return esc(b.name) + ' (' + esc(b.game) + ')'; }).join(', ')) + '</dl>';
    }
    Object.keys(items).forEach(function (k) {
      items[k].classList.toggle('on', k === key);
      items[k].classList.toggle('linked', !!linked[k]);
      items[k].classList.toggle('dim', k !== key && !linked[k]);
    });
    detail.innerHTML = html;
  }

  document.querySelectorAll('[data-board]').forEach(function (el) {
    el.addEventListener('click', function () {
      select('b:' + el.getAttribute('data-board'));
      root.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  detail.textContent = t(L.pick);
  select('b:sega1715376');
})();
