# Checklist Auto Chest Opener 3.2.0 — Retail 12.1.0

## 1. Installation et migration

- Sauvegarder `WTF/Account/.../SavedVariables/AutoChestOpener.lua` avant le premier test.
- Activer `/console scriptErrors 1`.
- Installer la 3.2.0 puis `/reload`.
- Lancer `/aco diag`.
- Vérifier : addon 3.2.0, Interface 120100, schéma DB 5, API critiques disponibles.
- Depuis une SavedVariables 3.1.1, vérifier que conteneurs, blacklist, statistiques, historique, loot et règles sont conservés.
- Vérifier qu'une installation migrée conserve ses anciens timings sous le profil **Personnalisé**.

## 2. Invariant principal : confirmation réelle

Avec au moins deux conteneurs présents :

- lancer `Ouvrir tout` ;
- observer l'onglet En attente ;
- vérifier qu'il n'existe jamais deux entrées simultanément en état de vérification ;
- vérifier qu'une seconde utilisation ne part pas tant que la première n'est pas confirmée ou échouée ;
- confirmer que les statistiques n'augmentent qu'après diminution réelle de la pile ;
- provoquer un refus et vérifier qu'aucun succès, historique d'ouverture ou loot confirmé n'est ajouté.

## 3. Anti-boucle

En profil Normal :

- provoquer deux échecs automatiques consécutifs pour le même Item ID ;
- vérifier l'apparition du circuit de sécurité ;
- vérifier que les autres entrées automatiques de ce même Item ID sont retirées ;
- relancer `Ouvrir tout` et vérifier que la raison de saut indique la suspension après échecs ;
- vérifier le temps restant dans l'éditeur de règles et `/aco diag` ;
- effectuer ensuite un essai explicite Assisté ; un succès confirmé doit remettre le compteur d'échecs consécutifs à zéro et lever le circuit.

Refaire un test en profil Prudent : un seul échec automatique doit suffire à déclencher le circuit.

## 4. Verrouillages et retries

- Tester un objet temporairement verrouillé.
- Vérifier que les contrôles de verrouillage sont bornés par le profil.
- Si l'objet reste verrouillé, vérifier l'échec `LOCKED_TIMEOUT` plutôt qu'une boucle infinie.
- Vérifier que le nombre de retries après `NOT_CONSUMED` ne dépasse pas la limite du profil.
- Vérifier qu'un retry manuel depuis la liste des échecs reste possible.

## 5. Mode Assisté

- Passer en mode Assisté.
- Mettre un conteneur en file et attendre `Clic requis`.
- Vérifier que seul un clic gauche réel sur le bouton visible déclenche l'action.
- Tester en combat : le bouton sécurisé ne doit pas être reconfiguré/utilisable tant que l'action est protégée.
- Déplacer le conteneur dans un autre slot avant le clic : la cible reste l'Item ID.
- Après clic, vérifier exactement le même mécanisme de confirmation par diminution de quantité.
- Vérifier qu'aucun code ne déclenche automatiquement le bouton Assisté.

## 6. Raisons de blocage

Tester au minimum :

- combat ;
- curseur occupé ;
- marchand ;
- échange ;
- hôtel des ventes ;
- courrier ;
- banque ;
- guilde si disponible ;
- fenêtre de loot ;
- blocage temporaire d'une règle ;
- limite de session ;
- circuit anti-échec.

La raison doit être explicite dans le centre de file ou dans le message de `Ouvrir tout`.

## 7. Profils

Tester :

- `/aco profile prudent` ;
- `/aco profile normal` ;
- `/aco profile fast`.

Après chaque commande, vérifier `/aco diag` et la sélection visuelle dans l'onglet En attente.

Le profil ne doit pas effacer le délai spécifique d'une règle de conteneur.

## 8. Filtres du centre de file

- Tester Tout, Actifs, Bloqués, Échecs.
- Vérifier que le filtre persiste après `/reload`.
- Vérifier que la vérification active est affichée avant les entrées en attente dans la vue Tout.
- Ne pas confondre l'ordre visuel avec un tri arbitraire : il doit rester représentatif de l'exécution réelle.

## 9. Règles et ACORULES1

- Créer plusieurs règles avec priorités, limites, source, note, blocage temporaire et blacklist.
- Exporter avec `/aco rules export`.
- Conserver la chaîne `ACORULES1`.
- Modifier/supprimer quelques règles puis les réimporter.
- Vérifier les caractères accentués, `%`, `;` et retours de ligne dans les notes.
- Vérifier qu'un blocage temporaire est restauré avec sa durée restante et non l'ancien timestamp absolu.
- Vérifier que les statistiques et l'historique ne sont pas modifiés par l'import.

## 10. Widget compact

- Sur une nouvelle base, vérifier qu'il est désactivé par défaut.
- Activer `/aco widget on`.
- Déplacer le widget puis `/reload` : la position doit être conservée.
- Désactiver `/aco widget off` : il doit disparaître même si une file existe.
- Réactiver et tester le bouton Assisté avec un clic réel.

## 11. Argent, butin et valeurs protégées

- Vérifier qu'une ouverture confirmée met à jour l'or si `GetMoney()` est accessible.
- Vérifier qu'aucune erreur arithmétique n'apparaît si une valeur monétaire devient inaccessible/protégée ; dans ce cas le delta d'or doit simplement être ignoré.
- Vérifier que les objets et monnaies restent suivis indépendamment du delta d'or.

## 12. Rapport de bug utile

Inclure :

- sortie complète de `/aco diag` ;
- erreur Lua complète ;
- Item ID ;
- profil et mode Auto/Assisté ;
- règle du conteneur ;
- état de la file ;
- raison affichée ;
- quantité avant/après ;
- test avec les autres addons désactivés si nécessaire.
