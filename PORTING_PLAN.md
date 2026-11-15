# Plan de portage : de la borne émulée à un 1942 natif moderne

<p align="center"><b>🇫🇷 Français</b> &nbsp;|&nbsp; <a href="PORTING_PLAN.en.md">🇬🇧 English</a></p>

## Comment 1942 est écrit (1984)

- 72 Ko d'assembleur Z80 écrits à l'ancienne.
- Pas d'OS, pas de système d'allocation, pas d'outils objets.
- Tout l'état du jeu tient dans 4 Ko de RAM, lisibles à chaque image. C'est ce qui rend la reconstruction possible.

| En 1984 | Aujourd'hui |
|---|---|
| Écrit à la main | outils actuels et assistance IA |
| Adresses fixes : score, position du joueur, chaque ennemi ont leur case (E000-EFFF) | variables, objets, allocations |
| Tableaux de slots : « l'ennemi n°7 » = 16 octets à une adresse, réutilisés | listes d'entités créées / détruites |
| Tout piloté par l'interruption vblank (RST 10h) | boucle de jeu avec pas de temps |
| Machines à états codées en octets | comportements, scripts |
| Vagues et trajectoires en tables dans les banques de ROM | fichiers de niveau, éditeurs |
| Entiers, virgule fixe, BCD pour le score | flottants |
| Écriture directe en mémoire vidéo / liste de sprites | moteur de rendu qui reçoit une scène |

## La méthode : le bateau de Thésée

On remplace le jeu planche par planche pendant qu'il tourne.
- L'oracle est la borne émulée.
- Elle est déterministe et calcule un hash de son état à chaque image.
- Après chaque planche remplacée, le hash doit rester identique.

1. Comprendre.
   - On nomme la RAM en observant ce qui bouge (droite : X du joueur ; ennemi abattu : score, slot, explosion).
   - Une cartographie du code dit déjà quelle routine écrit à quelle adresse.
   - Il manque un observateur de RAM en direct.
2. Remplacer à l'identique.
   - On intercepte une routine Z80 à son adresse d'entrée et on exécute sa version Pascal sur la même RAM.
   - On rejoue une partie : le hash doit rester identique à chaque image.
   - Ordre : score BCD, aléatoire et collision, puis joueur, ennemis, vagues et boss.
   - Fin de l'étape : le CPU principal n'exécute plus de Z80.
3. Moderniser le code.
   - Octets bruts, puis structures typées (`TPlayer`, `TEnemy[n]`, `TWave`), puis classes.
   - L'oracle compare alors l'état observable : score, positions, sprites.
4. Séparer le rendu.
   - La logique produit une scène : sprites, décor, texte.
   - Rendu rétro identique au pixel près à celui de l'émulateur.
   - Puis rendu FMeX modernisé, avec un décor interchangeable : 1942 n'a aucune collision avec le sol.
5. Données et son.
   - Les tables de vagues et de trajectoires passent des banques de ROM à du JSON (gs-core), éditable.
   - Le son passe d'abord par l'émulation AY, pilotée par le jeu natif.

Ces étapes conviennent bien aux outils d'IA : chaque routine réécrite se vérifie automatiquement contre l'oracle.

Règles :
- Pas fixe de 60 Hz et calculs entiers tant que la fidélité est l'objectif.
- La modernisation du gameplay vient après, comme un choix assumé.
- Rien de Capcom n'est distribué. Le jeu natif lit graphismes, sons et tables dans la ROM de l'utilisateur, comme le chargeur de cartouches actuel.

## Feuille de route

Fait :
- Borne émulée : 1942, Commando, Gun.Smoke et 1943.
- Commandes clavier et manette, configurables.

Portage de 1942 :
1. Enregistrer une partie de référence : `Cabinet.exe --record partie1.inp`.
2. Interception de routine par adresse sur le Z80, observateur de RAM.
3. Premières routines natives : score et aléatoire, vérifiées image par image.
4. Joueur, ennemis, vagues, boss, jusqu'au jeu entièrement natif.
5. Code modernisé, rendu FMeX, données en JSON.

Nouvelles cartes pour la borne, de la plus proche de l'existant à la plus lourde :

| Jeu | Matériel | À construire | Effort |
|---|---|---|---|
| Ghosts'n Goblins (Capcom, 1985) | Motorola 6809, Z80 son, 2 × YM2203 | puce 6809 et son banc de test, carte, cartouches | moyen : YM2203 déjà là |
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1 : 68000, Z80, YM2151, OKI MSM6295 | puces 68000, YM2151, MSM6295 ; vidéo CPS-1 (3 plans, sprites, priorités) | gros, ouvre toute la ludothèque CPS-1 |
| OutRun (Sega, 1986) | 2 × 68000, Z80, YM2151, SegaPCM, générateur de route, sprites zoomés | SegaPCM, route et zoom de sprites Sega, commandes analogiques | gros |
| Power Drift (Sega, 1988) | Y Board : 3 × 68000, sprites tournés et zoomés | rotation et zoom des sprites | le plus lourd |

- Le 68000 et le YM2151 servent à Ghouls'n Ghosts, OutRun et Power Drift : ils s'écrivent une seule fois.
- OutRun et Power Drift se jouent au volant : la borne devra gérer les commandes analogiques.

Commodore 64 :
- Jouer aux jeux C64 avec les manettes modernes, comme pour la borne : joystick et touche feu sur la manette, joystick 2 pour jouer à deux.
- Mettre en avant les jeux C64 récents, écrits et diffusés librement par des amateurs.
- Puces à écrire : 6510 (variante du 6502) et son banc de test, vidéo VIC-II, son SID, CIA 6526 (minuteries, joystick, clavier).
- Les jeux se chargent depuis des fichiers `.prg` et des cartouches `.crt`. Le lecteur de disquette 1541 vient plus tard, s'il le faut.
- Les ROMs système du C64 (KERNAL, BASIC, caractères) sont à fournir par l'utilisateur.

Salle d'arcade en 3D :
- Une salle avec plusieurs bornes, allumées ou éteintes. On en ajoute, on compose sa salle.
- Chaque borne fait tourner une carte de la borne actuelle : son image devient l'écran de la borne, son son devient une source 3D.
- Les bornes allumées tournent en mode démo. On s'approche d'une borne, on prend la manette, on joue.
- Rendu FMeX, effet d'écran cathodique. Un exemple à part (`samples/ArcadeRoom`) : la borne simple reste sans FMeX.
- Bornes aux couleurs de RetroLab : les décors d'origine des fabricants ne sont pas reproduits.
