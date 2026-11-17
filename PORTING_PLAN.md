# Feuille de route

<p align="center"><b>🇫🇷 Français</b> &nbsp;|&nbsp; <a href="PORTING_PLAN.en.md">🇬🇧 English</a></p>

## Ce qui est fait

- La borne émulée fait tourner sept jeux : 1942, Commando, Gun.Smoke, 1943 et Ghosts'n Goblins de Capcom, OutRun et Power Drift de Sega.
- Les processeurs Z80, MC6809 et MC68000 sont écrits, et chacun a son banc de test. Les puces son AY-3-8910, YM2203, YM2151 et la puce PCM de Sega sont écrites elles aussi.
- On joue au clavier ou à la manette, et les commandes se configurent depuis la borne.
- Dans OutRun et Power Drift, la manette vibre quand le volant de la borne d'origine vibrait.

## L'ordre de travail

1. RetroLab Room, la salle d'arcade en 3D. Elle n'utilise que les cartes existantes, et c'est elle qui pose les briques FMeX dont les remakes auront besoin : jusqu'à quatre manettes, le son, une boucle à 60 Hz et un rendu d'écran cathodique.
2. Beloved 43, le plus simple des remakes, qui reprend ces briques.
3. L'hommage à Ghosts'n Goblins. Avec la plateforme, quatre joueurs et la caméra, c'est le plus exigeant, et il profitera de tout ce que Beloved 43 aura mis en place.
4. De nouvelles cartes pour la borne, qui s'intercalent au fil de la liste des jeux à couvrir.
5. Le Commodore 64.

## RetroLab Room, la salle d'arcade en 3D

- C'est un programme à part (`samples/RetroLabRoom`). La borne actuelle, Cabinet, reste telle qu'elle est.
- La salle contient une borne par jeu du catalogue.
- Quand la ROM d'un jeu est présente, sa borne est allumée et tourne en mode démo. Un clic suffit pour jouer.
- Quand la ROM manque, la borne est éteinte, et un clic indique quel fichier ajouter.
- Chaque borne fait tourner la même carte émulée que Cabinet. Son image devient l'écran de la borne, et son son une source sonore placée dans la salle.
- Le rendu se fait avec FMeX, avec un effet d'écran cathodique. Les bornes portent les couleurs de RetroLab, sans reproduire les décors des fabricants.

## Les remakes en FMeX

Ces jeux sont des programmes natifs, qui n'ont besoin d'aucune ROM. Ils rendent hommage aux originaux avec des graphismes, des niveaux et des musiques entièrement refaits. Chacun deviendra une borne de RetroLab Room, toujours allumée, et le menu de Cabinet les indiquera comme « binaire natif ».

### Beloved 43, hommage à 1943

- C'est un shoot'em up vertical dans l'esprit de 1943, avec des avions du Pacifique, une barre d'énergie, des armes à ramasser et des boss géants.
- Les modèles 3D, les niveaux et la musique sont neufs. La musique évoque l'époque sans reprendre les mélodies d'origine.
- On y joue à deux en coopération.
- La borne émulée sert de référence pour retrouver les sensations du jeu : la vitesse, le rythme des vagues et la difficulté.

### Chevalier, l'hommage à Ghosts'n Goblins (nom pressenti)

- C'est un jeu de plateforme et de tir dans l'esprit de Ghosts'n Goblins : un chevalier qui perd son armure au premier coup, des armes à lancer, des cimetières et des démons.
- Tout est redessiné et les niveaux sont neufs. Certains rappellent ceux d'origine, pour que le lien avec le jeu soit évident.
- On y joue de un à quatre joueurs en même temps.
- La caméra est commune à tous et recule quand les joueurs s'écartent, jusqu'à une limite. Au-delà, le joueur resté en arrière est ramené vers les autres.
- La difficulté s'adapte au nombre de joueurs, et un joueur tombé peut être relevé par ses partenaires.
- Les ennemis s'en prennent au joueur le plus proche.

### Power Drift en 3D

- La carte de Power Drift est émulée. Le jeu aura aussi sa version FMeX, avec de vrais circuits en 3D.

## Raconter le fonctionnement

- Une présentation détaillée et animée du fonctionnement de l'émulateur : comment une carte est reconstruite, comment ses processeurs avancent ligne d'écran par ligne d'écran, et comment l'image se compose plan par plan.
- Pour chaque remake FMeX, une description détaillée de son fonctionnement, dans l'esprit des livres de Fabien Sanglard sur les moteurs de Wolfenstein 3D et de Doom.
- Ces descriptions pourront prendre la forme d'un livre au format ePub, lisible directement dans le jeu grâce à FMeX.book.

## Les nouvelles cartes pour la borne

| Jeu | Matériel | Ce qu'il reste à écrire | Effort |
|---|---|---|---|
| Ghouls'n Ghosts (Capcom, 1988) | CPS-1 : 68000, Z80, YM2151, OKI MSM6295 | la puce MSM6295 et la vidéo CPS-1 (trois plans, sprites, priorités) | moyen, et il ouvre une grande partie de la ludothèque Capcom |

- Le 68000 et le YM2151 ont été écrits pour OutRun, et la carte CPS-1 les réutilisera.
- Pour l'instant, OutRun et Power Drift se jouent avec les boutons : gauche et droite tournent le volant progressivement, les boutons 1 et 2 servent d'accélérateur et de frein, et le bouton 3 change de vitesse. Le stick et les gâchettes analogiques de la manette sont la prochaine étape pour ces deux jeux.

## Le Commodore 64

- L'idée est de jouer aux jeux C64 avec des manettes modernes, comme sur la borne : le joystick et le bouton de tir passent sur la manette, et une seconde manette sert de joystick 2 pour jouer à deux.
- On veut aussi mettre en avant les jeux C64 récents, écrits et diffusés librement par des amateurs.
- Il faudra écrire le processeur 6510 (une variante du 6502) avec son banc de test, la vidéo VIC-II, le son SID et le CIA 6526, qui gère les minuteries, le joystick et le clavier.
- Les jeux se chargeront depuis des fichiers `.prg` et des cartouches `.crt`. Le lecteur de disquette 1541 viendra plus tard, si le besoin s'en fait sentir.
- Les ROM système d'origine du C64 (KERNAL, BASIC et jeu de caractères) sont sous licence commerciale de Cloanto. Celui qui les possède peut les fournir, comme pour les jeux d'arcade.
- Pour qu'on puisse jouer dès la compilation, sans rien fournir, on s'appuiera sur les Open ROMs du projet MEGA65, une réécriture libre (GPL-3.0) de ces ROM, et sur des jeux amateurs dont les auteurs autorisent la diffusion.
