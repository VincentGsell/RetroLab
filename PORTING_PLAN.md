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
- Borne émulée : 1942, Commando, Gun.Smoke, 1943, Ghosts'n Goblins et OutRun.
- Commandes clavier et manette, configurables.

Ordre de travail :
1. RetroLab Room. Elle n'utilise que les cartes existantes et pose les briques FMeX communes : jusqu'à 4 manettes, son, boucle à 60 Hz, écran cathodique.
2. Beloved 43. C'est le remake le plus simple, il reprend ces briques.
3. Hommage à Ghosts'n Goblins. Plateforme, 4 joueurs et caméra : il profite de Beloved 43.
4. Nouvelles cartes, intercalées au fil de la liste des jeux à couvrir.
5. Commodore 64.

RetroLab Room, la salle d'arcade en 3D (`samples/RetroLabRoom`) :
- Un programme à part. Cabinet reste tel quel.
- Une salle avec une borne par jeu du catalogue : 1942, Commando, Gun.Smoke, 1943, Ghosts'n Goblins, OutRun.
- ROM présente : la borne est allumée, en mode démo. On clique, on joue.
- ROM absente : la borne est éteinte, et un clic dit quel fichier mettre.
- Chaque borne fait tourner une carte de la borne actuelle : son image devient l'écran, son son une source 3D.
- Rendu FMeX, effet d'écran cathodique, bornes aux couleurs de RetroLab (les décors d'origine des fabricants ne sont pas reproduits).

Beloved 43, hommage à 1943 en FMeX :
- Un jeu à part, dans l'esprit de 1943 : shoot'em up vertical, avions du Pacifique, barre d'énergie, armes à ramasser, boss géants.
- Modèles 3D, niveaux et musique neufs. La musique évoque l'époque sans reprendre les mélodies d'origine. Rien n'est repris de la ROM.
- Jouable à deux en coopération, sans aucune ROM : n'importe qui peut le télécharger et jouer.
- La borne émulée sert de référence pour les sensations : vitesse, rythme des vagues, difficulté.
- Il devient une borne de plus dans RetroLab Room, toujours allumée.

Hommage à Ghosts'n Goblins, en FMeX (nom à trouver) :
- Un jeu à part, dans l'esprit de Ghosts'n Goblins : plateforme et tir, un chevalier qui perd son armure au premier coup, armes à lancer, cimetières et démons.
- Tout est redessiné et les niveaux sont neufs. Certains rappellent ceux d'origine, pour que le lien soit évident.
- De 1 à 4 joueurs en simultané.
- Caméra commune qui recule quand les joueurs s'écartent, jusqu'à une limite. Au-delà, le joueur à la traîne est ramené vers les autres.
- La difficulté suit le nombre de joueurs.
- Un joueur tombé peut être relevé par les autres.
- Les ennemis visent le joueur le plus proche.
- Il devient lui aussi une borne de RetroLab Room.

Nouvelles cartes pour la borne, de la plus proche de l'existant à la plus lourde :

| Jeu | Matériel | À construire | Effort |
|---|---|---|---|
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1 : 68000, Z80, YM2151, OKI MSM6295 | puce MSM6295 ; vidéo CPS-1 (3 plans, sprites, priorités) | moyen, ouvre toute la ludothèque CPS-1 |
| Power Drift (Sega, 1988) | Y Board : 3 × 68000, sprites tournés et zoomés | rotation et zoom des sprites | le plus lourd |

- Le 68000 et le YM2151, écrits pour OutRun, servent aussi à Ghouls'n Ghosts et Power Drift.
- OutRun se joue pour l'instant avec les boutons : volant progressif sur gauche / droite, accélérateur et frein sur les boutons 1 et 2, rapport sur le bouton 3.
- Le stick et les gâchettes analogiques de la manette viendront avec Power Drift.

Commodore 64 :
- Jouer aux jeux C64 avec les manettes modernes, comme pour la borne : joystick et touche feu sur la manette, joystick 2 pour jouer à deux.
- Mettre en avant les jeux C64 récents, écrits et diffusés librement par des amateurs.
- Puces à écrire : 6510 (variante du 6502) et son banc de test, vidéo VIC-II, son SID, CIA 6526 (minuteries, joystick, clavier).
- Les jeux se chargent depuis des fichiers `.prg` et des cartouches `.crt`. Le lecteur de disquette 1541 vient plus tard, s'il le faut.
- Les ROMs système du C64 (KERNAL, BASIC, caractères) sont à fournir par l'utilisateur.
