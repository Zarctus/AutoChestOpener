# Auto Chest Opener 3.2.0

Addon World of Warcraft Retail ciblant **12.1.0 / Interface 120100**.

## Direction de la 3.2

Cette version privilégie la fiabilité avant la vitesse. Le cœur de l'addon applique désormais une règle simple : **une utilisation n'est jamais considérée comme réussie tant que la quantité du conteneur n'a pas réellement diminué**.

La file est également sérialisée : tant qu'une ouverture est en cours de vérification, aucune autre utilisation automatique n'est lancée. Cela évite qu'une diminution de pile provoquée par une première action soit attribuée à tort à une seconde.

## Sécurité et restrictions Blizzard

Deux chemins sont disponibles :

- **Automatique** : l'addon appelle l'API publique de conteneur, puis vérifie la consommation réelle.
- **Assisté** : l'addon prépare un bouton visible `SecureActionButtonTemplate`; le joueur effectue lui-même le clic matériel.

Il n'existe plus de fallback caché tentant de cliquer programmatiquement sur un bouton sécurisé. Si le client exige une action matérielle, l'addon l'explique et propose le mode Assisté au lieu d'essayer de contourner la protection.

## Circuit anti-boucle

Les échecs automatiques consécutifs sont suivis par type de conteneur. Une fois le seuil atteint :

- les nouvelles tentatives automatiques de cet objet sont suspendues temporairement ;
- ses autres entrées automatiques sont retirées de la file ;
- la raison et le temps restant sont visibles dans les règles et le diagnostic ;
- un succès confirmé réarme automatiquement le circuit ;
- un retry explicitement demandé par le joueur reste possible.

## Profils de file

Trois profils sont proposés :

- **Prudent** : vérifications plus longues, arrêt sur erreur, circuit déclenché dès le premier échec automatique ;
- **Normal** : compromis recommandé ;
- **Rapide** : vérifications plus courtes, sans retirer les garde-fous essentiels ;
- **Personnalisé** : utilisé automatiquement lors de la migration d'une ancienne 3.1 afin de préserver les réglages exacts déjà enregistrés.

Les profils règlent la mécanique de file et de vérification. Ils ne remplacent pas le délai global ou le délai spécifique défini dans une règle de conteneur.

## Centre de file

L'onglet **En attente** affiche :

- la vérification réellement active ;
- les éléments en attente ;
- l'état et la raison de chaque entrée ;
- le nombre de tentatives ;
- une ETA cohérente avec l'exécution sérialisée ;
- les échecs de session.

Filtres disponibles : **Tout**, **Actifs**, **Bloqués**, **Échecs**.

Les actions comprennent Pause/Reprise, Ouvrir le suivant, Vider la file, Retirer et Réessayer. Un échec `NOT_CONSUMED` ou `PROTECTED` propose directement un retry Assisté.

## Règles par conteneur

L'engrenage d'un conteneur permet de gérer :

- ouverture automatique ;
- délai spécifique ;
- limite d'ouvertures par session ;
- priorité ;
- blocage temporaire ;
- source et note ;
- blocage permanent.

Toutes les règles peuvent être exportées/importées avec le format versionné **ACORULES1**. L'import fusionne les règles sans réinitialiser les autres SavedVariables.

## Widget compact

Le widget de file est désormais réellement facultatif. Sur une nouvelle installation il est désactivé par défaut. Lorsqu'il est activé, sa position est conservée.

La 3.2 n'ajoute volontairement aucune nouvelle fenêtre flottante.

## SavedVariables

Le schéma passe à **5**. La migration conserve notamment :

- conteneurs suivis ;
- blacklist ;
- réglages ;
- statistiques ;
- historique ;
- résumé de butin ;
- règles par conteneur ;
- choix Automatique/Assisté.

## Commandes principales

| Commande | Action |
|---|---|
| `/aco` | Afficher ou masquer l'interface |
| `/aco openall` | Mettre en file tous les conteneurs éligibles |
| `/aco mode auto` | Mode automatique |
| `/aco mode assisted` | Mode assisté |
| `/aco next` | Préparer/avancer le prochain élément |
| `/aco queue` | Ouvrir le centre de file |
| `/aco queue clear` | Vider la file active |
| `/aco queue failures` | Effacer les échecs de session |
| `/aco profile prudent` | Profil de sécurité Prudent |
| `/aco profile normal` | Profil Normal |
| `/aco profile fast` | Profil Rapide |
| `/aco widget on` | Activer le widget compact |
| `/aco widget off` | Désactiver le widget compact |
| `/aco rules <itemID>` | Éditer les règles d'un conteneur |
| `/aco rules export` | Exporter toutes les règles |
| `/aco rules import` | Ouvrir l'import des règles |
| `/aco diag` | Diagnostic complet |
| `/aco resetui` | Réinitialiser uniquement l'UI |

## Installation

1. Fermer World of Warcraft.
2. Remplacer le dossier `Interface/AddOns/AutoChestOpener` par celui contenu dans le ZIP.
3. Relancer le jeu ou utiliser `/reload`.
4. Exécuter `/aco diag`.

Il n'est pas nécessaire de supprimer les SavedVariables pour passer depuis la 3.1.1.

## Choix de roadmap

L'export CSV de l'historique n'a pas été retenu dans cette version : il apporte de la valeur analytique, mais pratiquement aucune valeur de fiabilité. Le même raisonnement s'applique à un nouveau panneau compact près des sacs : le widget existant a été rendu facultatif plutôt que de créer une interface supplémentaire.

Consulter `TESTING.md` avant validation définitive en jeu.

## Licence

MIT.
