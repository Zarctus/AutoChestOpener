# Auto Chest Opener 3.1.1

Addon World of Warcraft Retail ciblant l’interface **120100 (12.1.0)**.

## Compatibilité 12.1

La 3.1.1 cible **Retail 12.1.0 / Interface 120100**. Les appels `C_Container`, `C_Item`, `C_TooltipInfo` et `C_AddOns` utilisés par l’addon ont été comparés aux définitions API live 12.1. Le détail de l’audit est disponible dans `COMPAT_12.1.md`.


## Nouveautés 3.1

### Centre de file

L’onglet **En attente** affiche maintenant la véritable file d’ouverture, et non une simple liste des conteneurs présents dans les sacs.

Chaque entrée expose :

- son état : attente, délai, blocage, ouverture, vérification, nouvel essai ou échec ;
- la raison exacte du blocage ou de l’échec ;
- le nombre de tentatives ;
- une estimation du délai restant ;
- les actions Réessayer et Retirer lorsque cela s’applique.

La file peut être mise en pause, reprise, vidée ou avancée manuellement.

### Mode assisté

Le mode **Assisté** prépare le prochain conteneur sur un véritable `SecureActionButtonTemplate`. Le joueur effectue alors un clic matériel sur **Ouvrir le suivant**.

Ce mode ne contourne pas les protections de Blizzard. Il fournit un chemin fiable lorsque l’utilisation automatique d’un objet est refusée par le client.

Le bouton sécurisé est disponible :

- dans l’onglet En attente ;
- dans le widget flottant de file lorsque la fenêtre principale est fermée.

### Règles par conteneur

Le bouton d’engrenage de chaque ligne ouvre un éditeur permettant de régler :

- l’ouverture automatique pour cet objet ;
- un délai spécifique, ou le délai global ;
- une limite d’ouvertures par session ;
- une priorité de file de -10 à 10 ;
- un blocage temporaire en minutes ;
- une source et une note personnelles ;
- un blocage permanent.

Les priorités ne permettent pas à un objet temporairement bloqué de retenir les autres entrées prêtes.

### Données et diagnostics

- Schéma de SavedVariables **4**, migré automatiquement depuis les versions précédentes.
- Succès, échecs, dernière réussite et dernier motif d’échec conservés par conteneur.
- Historique persistant borné des 50 derniers échecs.
- Limites de session appliquées dès la mise en file et à nouveau avant l’ouverture.
- Les piles sont correctement développées par `Ouvrir tout`.

## Installation

1. Fermer World of Warcraft.
2. Extraire le dossier `AutoChestOpener` dans :

   `World of Warcraft/_retail_/Interface/AddOns/`

3. Vérifier que ce fichier existe directement dans le dossier :

   `AutoChestOpener/AutoChestOpener.toc`

4. Relancer le jeu ou utiliser `/reload`.

Les données 3.0.x sont conservées et migrées automatiquement. Une sauvegarde du dossier `WTF` reste recommandée avant un test majeur.

## Commandes principales

| Commande | Action |
|---|---|
| `/aco` | Afficher ou masquer l’interface |
| `/aco add <itemID>` | Ajouter un conteneur |
| `/aco remove <itemID>` | Retirer un conteneur |
| `/aco openall` | Mettre en file tous les conteneurs éligibles |
| `/aco mode auto` | Utiliser le mode automatique |
| `/aco mode assisted` | Utiliser le mode assisté |
| `/aco next` | Préparer ou accélérer le prochain élément |
| `/aco queue` | Ouvrir directement le centre de file |
| `/aco queue clear` | Vider la file active |
| `/aco queue failures` | Effacer les échecs affichés |
| `/aco rules <itemID>` | Ouvrir l’éditeur de règles d’un conteneur |
| `/aco diag` | Afficher les diagnostics 120100 et de file |
| `/aco resetui` | Réinitialiser la fenêtre |

Un raccourci **Préparer/Ouvrir le prochain élément** est également disponible dans les raccourcis clavier du jeu.

## Limite importante de l’API Retail

Certaines utilisations d’objets peuvent être refusées silencieusement lorsque le client exige une action matérielle réelle. L’addon :

- vérifie que la quantité du conteneur a réellement diminué ;
- n’enregistre jamais une ouverture avant cette confirmation ;
- effectue des essais limités en mode automatique ;
- propose le mode assisté pour effectuer le clic sécurisé légitime.

## Tests

Consulter `TESTING.md`. La validation syntaxique et les simulations fournies ne remplacent pas un test dans le client Retail 12.1.0.

## Licence

MIT.
