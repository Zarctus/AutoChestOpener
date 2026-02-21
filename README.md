# Auto Chest Opener

![Version](https://img.shields.io/badge/version-1.3.5-blue)
![WoW Version](https://img.shields.io/badge/WoW-12.0.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Description

**Auto Chest Opener** est un addon élégant et moderne pour World of Warcraft qui ouvre automatiquement vos coffres, sacs et conteneurs après les avoir reçus dans votre inventaire.

## Fonctionnalités

- 🎁 **Ouverture automatique** des coffres et conteneurs
- ⏱️ **Délai personnalisable** (0 à 10 secondes)
- 🖱️ **Glisser-déposer** pour ajouter des items
- 🔢 **Ajout par ID** d'item
- 🎨 **Interface moderne** avec système d'onglets
- 📊 **Statistiques détaillées** (total ouvert, top items, timestamps)
- � **Tracking de l'or** gagné (total et par session)
- 📜 **Historique** des 50 dernières ouvertures avec or gagné
- 📍 **Bouton minimap** avec clic gauche/droit
- 🔊 **Notifications sonores** optionnelles
- 💬 **Notifications dans le chat** optionnelles
- 📤 **Import/Export** de listes de conteneurs

## Installation

1. Téléchargez l'addon
2. Extrayez le dossier `AutoChestOpener` dans :
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Redémarrez World of Warcraft ou tapez `/reload`

## Utilisation

### Interface graphique

- Cliquez sur le **bouton minimap** (icône de coffre) ou tapez `/aco`
- **Glissez un item** dans la zone de dépôt pour l'ajouter
- Ou entrez l'**ID de l'item** et cliquez sur "Ajouter"
- Configurez les options selon vos préférences

### Commandes slash

| Commande | Description |
|----------|-------------|
| `/aco` | Ouvre l'interface |
| `/aco add <itemID>` | Ajoute un conteneur par ID |
| `/aco remove <itemID>` | Retire un conteneur |
| `/aco list` | Liste tous les conteneurs |
| `/aco openall` | Ouvre tous les conteneurs maintenant |
| `/aco toggle` | Active/Désactive l'addon |
| `/aco delay <sec>` | Change le délai (0-30s) |
| `/aco stats` | Affiche les statistiques |
| `/aco history` | Affiche l'historique récent |
| `/aco clearstats` | Réinitialise les statistiques |
| `/aco clearhistory` | Efface l'historique |
| `/aco export` | Exporte la liste |
| `/aco import` | Importe une liste |
| `/aco debug` | Mode debug |

### Bouton Minimap

- **Clic gauche** : Ouvre l'interface
- **Clic droit** : Active/Désactive l'addon
- **Glisser** : Déplace le bouton autour de la minimap

### Astuce

- Maintenez **ALT + Clic gauche** sur un lien d'item dans le chat pour l'ajouter directement à la liste !

## Comment ça marche

1. Ajoutez les IDs des coffres/sacs que vous voulez ouvrir automatiquement
2. L'addon détecte automatiquement les items avec un sort "Ouvrir"
3. Quand vous recevez un item de la liste dans votre inventaire, il sera ouvert après le délai configuré
4. L'ouverture ne se fait pas en combat pour éviter les problèmes

## Exemples d'items compatibles

- Coffres de donjon
- Sacs de butin
- Caisses de quête
- Conteneurs d'événements
- Tout item avec le sort "Ouvrir"

## Configuration

### Paramètres disponibles

| Option | Description |
|--------|-------------|
| Activer l'ouverture | Active/désactive l'addon |
| Afficher les notifications | Messages dans le chat |
| Jouer les sons | Effets sonores lors de l'ouverture |
| Délai avant ouverture | Temps d'attente (0-10 secondes) |

## Dépannage

**L'addon ne s'ouvre pas :**
- Vérifiez que le dossier est bien dans `Interface\AddOns\`
- Vérifiez que le dossier s'appelle exactement `AutoChestOpener`

**Un item n'est pas ouvert automatiquement :**
- Vérifiez qu'il est bien dans la liste
- Vérifiez que l'addon est activé
- Certains items nécessitent des conditions spéciales (niveau, profession, etc.)

**Erreurs en combat :**
- Normal ! L'addon attend la fin du combat pour ouvrir les items

## Changelog

### Version 1.2.0
- ✨ **Nouveau:** Onglet Statistiques avec compteurs détaillés
- ✨ **Nouveau:** Onglet Historique des 50 dernières ouvertures
- ✨ **Nouveau:** Top 5 des items les plus ouverts
- ✨ **Nouveau:** Commandes `/aco stats` et `/aco history`
- ✨ **Nouveau:** Boutons réinitialisation stats/historique
- 💰 **Nouveau:** Tracking de l'or gagné (total et par session)
- 💰 **Nouveau:** Affichage de l'or dans l'historique
- 🎨 Interface avec système d'onglets (Conteneurs, Stats, Historique)
- ⚡ Optimisations de performance (upvalues locales, cache)
- 🌐 Support multi-langues étendu (russe, coréen)

### Version 1.1.0
- ⚡ Optimisations de performance
- 🔧 Cache des items conteneurs
- 📦 Import/Export de listes

### Version 1.0.0
- Première version
- Interface moderne style nouvelle UI WoW
- Drag & drop pour ajouter des items
- Ajout par ID
- Paramètres personnalisables
- Bouton minimap
- Commandes slash complètes

## Licence

MIT License - Libre d'utilisation et de modification

## Crédits

Créé par **Zayu**

---

*Enjoy your automatic chest opening! 🎁*


### 1.3.3
- L'ouverture est automatiquement mise en attente si vous êtes en combat ou si une fenêtre sensible est ouverte (marchand/banque/courrier/HV/échange). Elle reprend automatiquement dès que c'est possible.
