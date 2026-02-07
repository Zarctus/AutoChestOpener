# Textures pour AutoChestOpener

Place ici ton image d'icône personnalisée qui sera utilisée par l'addon.

Nom de fichier attendu (par défaut):
- `treasure.tga`

Recommandations :
- Format : TGA (ou BLP si tu préfères, mais TGA est simple et compatible).
- Taille : 64x64 ou 128x128 (puissance de deux recommandée).
- Canal alpha : inclus si tu veux de la transparence.

Exemples de conversion (ImageMagick) :

```bash
# Convertir un PNG en TGA (Linux/macOS/Windows avec ImageMagick)
magick convert input.png -resize 128x128 -background none -flatten -alpha on treasure.tga
```

Emplacement final attendu dans l'archive de l'addon :
`Interface/AddOns/AutoChestOpener/textures/treasure.tga`

Après avoir ajouté le fichier :
1. Lancer WoW et exécuter `/reload`.
2. Vérifier l'icône du TOC et l'icône dans l'UI (en-tête / minimap selon l'usage).

Si tu veux, je peux aussi :
- Générer un placeholder `.tga` basique et l'ajouter (mais ce fichier sera une image factice),
- Ou patcher `UI.lua` pour utiliser cette icône comme fallback si un item n'a pas d'icône.

Dis-moi si tu veux que je crée un placeholder image maintenant.