# Site portfolio — Cellule Infographie Groupe IMING

Site vitrine de la cellule infographie (visualisation 3D pour architectes,
aménageurs et industriels). Le contenu (`Portfolio/`) devient automatiquement
des pages du site — pas de mise à jour manuelle d'aucune ligne de code pour
ajouter un projet.

**Site en ligne :** https://smaublanc.github.io/iming-cellule-infographie/
(GitHub Pages, gratuit, toujours disponible — pas besoin que ce PC soit
allumé)

---

## Reprendre le travail depuis un autre PC (avec Claude Code)

1. `git clone https://github.com/smaublanc/iming-cellule-infographie.git`
2. Ouvre Claude Code dans ce dossier
3. Ce README suffit à Claude pour avoir tout le contexte (conventions,
   scripts, structure) — pas besoin de tout réexpliquer

Point important : ce dépôt couvre le **site statique** (maquette + contenu).
La partie **WordPress** (thème PHP, import en base) tourne via **Local by
WP Engine** sur la machine d'origine (`C:\Users\smaublanc\Local Sites\iming-studio\`)
et n'est *pas* dans ce dépôt — elle est spécifique à cette installation.
Depuis une autre machine, on peut continuer à faire évoluer le site statique
et le republier normalement ; retrouver le site WordPress nécessite Local
installé sur cette machine-là (ou une réinstallation ailleurs, à faire au
cas par cas).

---

## Structure

```
Portfolio/
  Images/{Categorie}/{NomProjet}/     -- Architecture, Autoroute, Design, Industrie, IRVE
    *.jpg                             -- photos du projet
    _photo.jpg                        -- underscore = vignette choisie (voir conventions)
    vignette.mp4 / .webm              -- video animee au survol sur la page d'accueil
    texte.txt                         -- CLIENT/ARCHITECTE/ANNEE + texte FR/EN
  Films/{NomProjet}/                  -- vrais films livres (pas une galerie photo)
    *.mp4                             -- le film lui-meme (lecteur avec controles sur sa page)
    *.jpg                             -- affiche/poster
    texte.txt

Portfolio-web/                        -- GENERE (compress-images.ps1) -- versions
  {meme structure que Portfolio/}        web-optimisees des photos, jamais les
                                          originaux touches. Committe sur Git :
                                          c'est ce que le site sert reellement.

maquette/                             -- le site lui-meme (HTML/CSS/JS statique)
  index.html, projet.html, equipe.html
  js/data.js                          -- GENERE depuis Portfolio/ (ne pas editer a la main)
  js/main.js, css/style.css
  preview-local.ps1                   -- serveur local pour previsualiser

scan-portfolio.ps1                    -- scanne Portfolio/ -> portfolio-inventory.json
compress-images.ps1                   -- genere Portfolio-web/ (incremental, voir plus bas)
generate-data-js.ps1                  -- regenere maquette/js/data.js + sitemap.xml
maj-portfolio.ps1                     -- lance les trois scripts ci-dessus d'affilee
publier.ps1                           -- maj-portfolio.ps1 + commit + push sur GitHub

sitemap.xml, robots.txt, 404.html, index.html (racine)  -- GENERE/statique, SEO + lien racine propre
```

## Photos web-optimisees (Portfolio-web/)

Les fichiers dans `Portfolio/` sont les sources (qualité livraison, jamais
modifiées). `compress-images.ps1` génère dans `Portfolio-web/` deux versions
par photo, redimensionnées et recompressées en JPEG :
- `<nom>.card.jpg` — ~900px de large max, pour les vignettes de grille
- `<nom>.jpg` — ~1800px de large max, pour la galerie / le hero de page projet

C'est **incrémental** : une photo déjà à jour (dérivée plus récente que la
source) n'est jamais retraitée — le script peut tourner à chaque mise à jour
sans ralentir. Gain typique observé : ~263 Mo de sources → ~63 Mo de dérivées
(les deux tailles cumulées), sans perte visible. Les vidéos (vignette.mp4,
films) ne sont pas concernées — pas d'encodeur vidéo disponible sans
dépendance externe ; les compresser à l'export (Adobe Media Encoder) reste
manuel.

## Conventions de contenu (dossier projet)

- **Nom de dossier** : `Client_NomDuProjet` -> titre affiché "Client — Nom Du Projet".
  Un dossier dont le nom commence par `0` n'est **jamais publié** (utile pour
  préparer un projet sans qu'il apparaisse encore).
- **Photo de couverture** : le fichier image dont le nom commence par `_`
  (ex. `_Salon0002.jpg`) est utilisé en priorité comme vignette sur la page
  d'accueil et en tête de la page projet. Sans `_`, une photo est choisie
  automatiquement et reste stable (ne change pas à chaque régénération).
- **Vignette vidéo** (catégories Images uniquement, pas Films) : un fichier
  vidéo dans le dossier devient l'animation au survol de la carte sur la
  page d'accueil. S'il n'y a qu'une seule vidéo dans le dossier, elle est
  prise automatiquement quel que soit son nom. S'il y en a plusieurs, seule
  celle nommée exactement `vignette.mp4` (ou `.webm`) est prise — sinon
  `scan-portfolio.ps1` te préviendra dans sa sortie.
- **texte.txt** :
  ```
  CLIENT: ...
  ARCHITECTE: ...   (optionnel)
  ANNEE: ...         (optionnel)

  [FR]
  Texte en français.

  [EN]
  Texte en anglais. (optionnel : le texte FR est réutilisé si absent)
  ```
  Sans texte FR, la page affiche "Description à venir." plutôt que d'inventer
  un texte.

## Après avoir ajouté/modifié un projet

1. Double-clique **`Mettre-a-jour-le-site.bat`** — régénère le site à partir
   du contenu réel du dossier `Portfolio/` et te dit ce qu'il a trouvé
   (nouveaux projets, vignettes détectées ou ignorées, etc.)
2. Pour prévisualiser en local avant de publier : double-clique
   **`maquette/Ouvrir-apercu.bat`**
3. Pour publier en ligne (GitHub Pages) : double-clique **`Publier.bat`**
   — combine l'étape 1 et un `git add`/`commit`/`push`. Le site en ligne se
   met à jour en ~1 minute.

## Catégories

`architecture`, `autoroute`, `design`, `industrie`, `irve`, `films` — définies
dans `maquette/js/data.js` (généré) et `maj-portfolio.ps1`. Ajouter une
nouvelle catégorie = créer le dossier correspondant dans `Portfolio/Images/`
et l'ajouter à la liste `CATEGORIES` dans `generate-data-js.ps1`.

## Pièges connus

- **`.nojekyll` à la racine — NE PAS SUPPRIMER.** GitHub Pages traite les
  sites avec Jekyll par défaut, qui ignore silencieusement tout fichier/
  dossier commençant par `_` — exactement la convention utilisée pour les
  photos de couverture (`_Pers0001.jpg`, etc.). Sans ce fichier, toutes les
  vignettes "_" renvoient un 404 en ligne alors que le reste du site
  fonctionne, ce qui rend le bug difficile à repérer (le dépôt Git contient
  bien tous les fichiers — c'est uniquement le *build* Pages qui les
  ignorait). Symptôme si ça revient : impression que des images "ne se
  chargent pas" alors que `git status`/`git ls-files` montrent tout présent.

## Historique / décisions notables

- Design inspiré de bocostudio.com, adapté pour ne pas être un copier-coller
  (typographie Plus Jakarta Sans + Geist Mono, palette marine/rouge IMING).
- Bilingue FR/EN géré côté client (`data-i18n-fr`/`data-i18n-en` sur les
  éléments), pas de plugin de traduction.
- Le thème WordPress (séparé, voir plus haut) réplique exactement le même
  design/comportement — les deux sont maintenus en parallèle.
- Les images de la grille et de la galerie apparaissent progressivement au
  scroll (classe `.reveal` + `IntersectionObserver` dans `main.js`/`theme.js`,
  respecte `prefers-reduced-motion`) plutôt que de charger d'un coup.
- Grille homepage volontairement asymétrique plutôt qu'un mur de vignettes
  identiques : une carte sur 5 en format large (`is-featured`, 16:10, 2
  colonnes), une sur 11 en cinémascope (`is-wide`, 21:9, 3 colonnes), jamais
  les deux en même temps (logique `else if` dans `renderCard()`/
  `project-card.php`). Repli propre en 1 colonne / 4:5 sous 1100px. Zoom au
  survol volontairement très subtil (1.02, pas 1.05+) — inspiré de la
  retenue de mir.no, qui n'en fait aucun.
- Balises Open Graph / Twitter Card : génériques sur la maquette (une seule
  page `projet.html?slug=...` sert tous les projets, donc l'aperçu ne varie
  pas par projet — pour ça il faudrait une page statique par projet, pas fait).
  Sur WordPress en revanche, chaque page est rendue côté serveur : les
  balises OG y sont **réellement par projet** (titre, extrait du texte FR,
  image mise en avant) — voir `header.php`.
- `sitemap.xml` régénéré à chaque `generate-data-js.ps1` (liste les projets
  courants automatiquement) ; attention à ne pas réintroduire de BOM UTF-8
  en tête de fichier si ce script est retouché (`Out-File -Encoding utf8` en
  ajoute un, invalide pour un sitemap XML strict — d'où l'écriture via
  `[System.IO.File]::WriteAllText` avec un `UTF8Encoding($false)`).
