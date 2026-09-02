function assetUrl(path) {
  if (!path) return "";
  return (
    "../" +
    path
      .split("/")
      .map((segment) => encodeURIComponent(segment))
      .join("/")
  );
}

// Photos : servies via leurs versions web-optimisees (Portfolio-web/, voir
// compress-images.ps1) plutot que le fichier source (souvent 2-4 Mo pour
// une image affichee a 300px de large). "card" = vignette de grille,
// "full" = galerie/hero de page projet. Videos non concernees (pas de
// derivee generee pour elles) : on garde le fichier source tel quel.
function webImageUrl(path, size) {
  if (!path) return "";
  if (!/\.(jpe?g|png)$/i.test(path)) return assetUrl(path);
  const webPath = path.replace(/^Portfolio\//, "Portfolio-web/");
  const suffixed = size === "card" ? webPath.replace(/\.(jpe?g|png)$/i, ".card.jpg") : webPath.replace(/\.(jpe?g|png)$/i, ".jpg");
  return assetUrl(suffixed);
}

function categoryLabel(key) {
  const found = CATEGORIES.find((c) => c.key === key);
  return found ? found.label : key;
}

function escapeHtml(str) {
  const map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  return String(str).replace(/[&<>"']/g, (c) => map[c]);
}

// Choix de la vignette : une image dont le nom de fichier commence par "_"
// est prioritaire (ex. "_Salon0002.jpg"). Sinon, choix pseudo-aléatoire mais
// stable par projet (dérivé du slug, ne change pas à chaque rendu de page).
function pickCover(project) {
  if (!project.images || project.images.length === 0) return null;
  const marked = project.images.find((img) => img.split("/").pop().startsWith("_"));
  if (marked) return marked;
  let hash = 0;
  for (const ch of project.slug) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return project.images[hash % project.images.length];
}

// Convention du fichier texte.txt à la racine de chaque dossier projet :
//   CLIENT: ...
//   ARCHITECTE: ...   (optionnel)
//   ANNEE: ...        (optionnel)
//
//   [FR]
//   Texte en français.
//
//   [EN]
//   Texte en anglais. (optionnel : si absent, le texte FR est réutilisé)
function parseProjectText(raw) {
  const frIdx = raw.search(/\[FR\]/i);
  const header = frIdx === -1 ? raw : raw.slice(0, frIdx);
  const body = frIdx === -1 ? raw : raw.slice(frIdx);

  const meta = {};
  // "client" a un cas particulier : une ligne "CLIENT:" presente mais VIDE
  // signifie "ne pas afficher de client" (ex. le client se confond avec
  // l'architecte) -- a distinguer de l'ABSENCE de la ligne, qui garde le
  // repli habituel sur le nom derive du dossier (voir clientSpecified).
  let clientSpecified = false;
  header.split("\n").forEach((line) => {
    const m = line.match(/^([A-Za-zÀ-ÿ ]+):\s*(.*)$/);
    if (!m) return;
    const key = m[1].trim().toLowerCase();
    const value = m[2].trim();
    if (key === "client") {
      clientSpecified = true;
      meta[key] = value;
    } else if (value) {
      meta[key] = value;
    }
  });

  const enIdx = body.search(/\[EN\]/i);
  let frText = (enIdx === -1 ? body : body.slice(0, enIdx)).replace(/\[FR\]/i, "").trim();
  let enText = (enIdx === -1 ? "" : body.slice(enIdx).replace(/\[EN\]/i, "")).trim();

  // Un lien colle seul sur sa ligne (ex. vers la page du projet sur le
  // site de l'architecte) : on le sort du texte pour l'afficher comme un
  // vrai lien plutot que de laisser une URL brute au milieu du paragraphe.
  const urlRe = /^https?:\/\/\S+$/m;
  let link = null;
  const frLinkMatch = frText.match(urlRe);
  if (frLinkMatch) {
    link = frLinkMatch[0];
    frText = frText.replace(frLinkMatch[0], "").replace(/\n{3,}/g, "\n\n").trim();
  }
  const enLinkMatch = enText.match(urlRe);
  if (enLinkMatch) {
    link = link || enLinkMatch[0];
    enText = enText.replace(enLinkMatch[0], "").replace(/\n{3,}/g, "\n\n").trim();
  }

  return {
    client: meta["client"],
    clientSpecified: clientSpecified,
    architecte: meta["architecte"],
    annee: meta["annee"] || meta["année"],
    fr: frText,
    en: enText || frText,
    link: link,
  };
}

async function loadProjectText(project) {
  if (!project.textFile) return null;
  try {
    const res = await fetch(assetUrl(project.textFile));
    if (!res.ok) return null;
    return parseProjectText(await res.text());
  } catch (err) {
    return null;
  }
}

function projectFolder(project) {
  if (!project.images || project.images.length === 0) return null;
  const first = project.images[0];
  return first.slice(0, first.lastIndexOf("/"));
}

// Convention : une vidéo nommée vignette.mp4 (ou .webm) à la racine du
// dossier projet devient prioritaire comme vignette animée sur la page
// d'accueil (survol = lecture). N'affecte pas la page projet.
const VIGNETTE_VIDEO_NAMES = ["vignette.mp4", "vignette.webm"];
const VIGNETTE_PROBE_TIMEOUT_MS = 1500;

async function detectVignetteVideo(project) {
  const folder = projectFolder(project);
  if (!folder) return null;
  for (const name of VIGNETTE_VIDEO_NAMES) {
    const relPath = `${folder}/${name}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), VIGNETTE_PROBE_TIMEOUT_MS);
    try {
      const res = await fetch(assetUrl(relPath), { method: "HEAD", signal: controller.signal });
      if (res.ok) return relPath;
    } catch (err) {
      // pas de serveur / fichier absent / délai dépassé : on essaie le suivant
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

// Apparition progressive au scroll pour les images marquees ".reveal"
// (grille + galerie projet) : plus fidele au metier (un rendu 3D qui se
// "revele") qu'un chargement brutal, et gratuit en dependances (juste un
// IntersectionObserver). Respecte prefers-reduced-motion.
let revealObserver = null;
function observeReveals(root) {
  const scope = root || document;
  const els = scope.querySelectorAll(".reveal:not(.is-visible)");
  if (!els.length) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    els.forEach((el) => el.classList.add("is-visible"));
    return;
  }
  if (!revealObserver) {
    revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        });
      },
      { rootMargin: "120px 0px", threshold: 0.05 }
    );
  }
  els.forEach((el) => revealObserver.observe(el));
}

function renderCard(project, index) {
  const cover = pickCover(project);
  const img = cover ? `<img class="card-img reveal" src="${webImageUrl(cover, "card")}" alt="${escapeHtml(project.title)}" loading="lazy" />` : "";
  // La video en boucle au survol ne concerne que les vignettes des projets
  // "Images" (vignette.mp4 dediee). Pour "Films", project.video est le
  // vrai film livre au client : on ne le boucle jamais en muet sur la
  // grille, on garde juste la vignette fixe (le film se regarde sur sa
  // page projet, cf. initProjectPage).
  const video = project.video && project.category !== "films" ? `<video class="card-video" src="${assetUrl(project.video)}" muted loop playsinline preload="metadata"></video>` : "";
  // Rythme editorial plutot qu'une grille uniforme : une carte sur 5 passe
  // en format large (16:10, 2 colonnes) ; plus rarement (une sur 11, jamais
  // en meme temps que "large") une carte casse le rythme en format
  // cinemascope (21:9, 3 colonnes) -- inspire des ruptures de grille
  // asymetriques de Kilograph/Squint-Opera plutot qu'un mur de vignettes
  // identiques.
  let variant = "";
  if (index % 5 === 0) variant = " is-featured";
  else if (index % 11 === 7) variant = " is-wide";
  const num = String(index + 1).padStart(2, "0");
  return `
    <a class="card${variant}" href="projet.html?slug=${project.slug}" data-category="${escapeHtml(project.category)}">
      <span class="card-media">
        ${img}
        ${video}
        <span class="card-index">${num}</span>
        <span class="card-frame"></span>
      </span>
      <span class="card-caption">
        <span class="card-title">${escapeHtml(project.title)}</span>
        <span class="card-meta">${escapeHtml(categoryLabel(project.category))} · ${escapeHtml(project.client)}</span>
      </span>
    </a>
  `;
}

async function initGrid() {
  const grid = document.querySelector("[data-grid]");
  if (!grid) return;

  await Promise.all(
    PROJECTS.map(async (p) => {
      if (p.video) return;
      const found = await detectVignetteVideo(p);
      if (found) p.video = found;
    })
  );

  grid.innerHTML = PROJECTS.map((p, i) => renderCard(p, i)).join("");

  const filterButtons = document.querySelectorAll("[data-filter]");
  filterButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      filterButtons.forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");
      const value = btn.getAttribute("data-filter");
      grid.querySelectorAll(".card").forEach((card) => {
        const match = value === "tout" || card.getAttribute("data-category") === value;
        card.style.display = match ? "" : "none";
      });
    });
  });

  grid.querySelectorAll(".card").forEach((card) => {
    const video = card.querySelector(".card-video");
    if (!video) return;
    card.addEventListener("mouseenter", () => {
      video.muted = true;
      video.play().catch((err) => console.warn("Lecture vidéo bloquée pour", video.src, "-", err.name, err.message));
    });
    card.addEventListener("mouseleave", () => {
      video.pause();
      video.currentTime = 0;
    });
  });

  observeReveals(grid);
}

function initHero() {
  const mosaic = document.querySelector("[data-hero-mosaic]");
  if (mosaic) {
    const covers = PROJECTS.map((p) => pickCover(p)).filter(Boolean);
    if (covers.length) {
      const tiles = Array.from({ length: 18 }, (_, i) => covers[i % covers.length]);
      mosaic.innerHTML = tiles
        .map((img, i) => `<img src="${webImageUrl(img, "card")}" alt="" loading="${i < 3 ? "eager" : "lazy"}" />`)
        .join("");
    }
  }

  const count = document.querySelector("[data-hero-count]");
  if (count) {
    const nbProjects = PROJECTS.length;
    const nbCats = CATEGORIES.length;
    const fr = `<b>${nbProjects}</b> projets &middot; <b>${nbCats}</b> spécialités`;
    const en = `<b>${nbProjects}</b> projects &middot; <b>${nbCats}</b> specialties`;
    count.setAttribute("data-i18n-fr", fr);
    count.setAttribute("data-i18n-en", en);
    count.innerHTML = fr;
  }
}

function initHeader() {
  const header = document.querySelector("[data-header]");
  if (!header) return;
  const onScroll = () => {
    header.classList.toggle("is-scrolled", window.scrollY > 40);
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const burger = document.querySelector("[data-burger]");
  const mobileNav = document.querySelector("[data-mobile-nav]");
  if (burger && mobileNav) {
    burger.addEventListener("click", () => {
      mobileNav.classList.toggle("is-open");
      burger.classList.toggle("is-open");
    });
  }

  const langButtons = document.querySelectorAll("[data-lang]");
  langButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      langButtons.forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");
      const lang = btn.getAttribute("data-lang");
      document.querySelectorAll("[data-i18n-fr]").forEach((el) => {
        el.innerHTML = lang === "en" ? el.getAttribute("data-i18n-en") : el.getAttribute("data-i18n-fr");
      });
      // Même mécanisme que assets/js/theme.js (thème WordPress) : variante
      // "-text" pour du contenu échappé via textContent (pas de HTML brut).
      document.querySelectorAll("[data-i18n-fr-text]").forEach((el) => {
        el.textContent = lang === "en" ? el.getAttribute("data-i18n-en-text") : el.getAttribute("data-i18n-fr-text");
      });
    });
  });
}

// Bandeau "autres projets" : la barre de defilement native est masquee
// (esthetique), donc sans ceci il n'y a aucun moyen visible de naviguer
// dedans au clic -- seul un geste de scroll horizontal (peu decouvrable
// a la souris) le permettait.
function initOthersNav(container) {
  const row = container.querySelector("[data-others-row]");
  const prevBtn = container.querySelector("[data-others-prev]");
  const nextBtn = container.querySelector("[data-others-next]");
  if (!row || !prevBtn || !nextBtn) return;

  const scrollByPage = (dir) => {
    row.scrollBy({ left: dir * row.clientWidth * 0.8, behavior: "smooth" });
  };
  prevBtn.addEventListener("click", () => scrollByPage(-1));
  nextBtn.addEventListener("click", () => scrollByPage(1));

  const updateArrows = () => {
    const max = row.scrollWidth - row.clientWidth;
    prevBtn.disabled = row.scrollLeft <= 4;
    nextBtn.disabled = row.scrollLeft >= max - 4;
  };
  row.addEventListener("scroll", updateArrows, { passive: true });
  window.addEventListener("resize", updateArrows);
  updateArrows();
}

async function initProjectPage() {
  const container = document.querySelector("[data-project]");
  if (!container) return;

  const params = new URLSearchParams(window.location.search);
  const slug = params.get("slug");
  const project = PROJECTS.find((p) => p.slug === slug) || PROJECTS[0];

  document.title = `${project.title} — Groupe IMING`;

  const parsed = (await loadProjectText(project)) || {};
  // "CLIENT:" vide et explicite dans texte.txt = volontairement pas de
  // client affiche (ex. le client se confond avec l'architecte) -- sinon
  // repli sur le nom derive du dossier, comme avant.
  const client = parsed.clientSpecified ? parsed.client : (parsed.client || project.client);
  const architecte = parsed.architecte;
  const annee = parsed.annee;
  const frText = parsed.fr || "Description à venir.";
  const enText = parsed.en || parsed.fr || "Description coming soon.";

  // "Films" : le dossier contient le vrai film livre + une image d'affiche
  // (poster). Pas de galerie photo classique ici -- on affiche un lecteur
  // video, avec l'affiche comme image de patience avant lecture.
  const isFilm = project.category === "films" && project.video;

  const galleryHtml = project.images
    .map(
      (img, i) => `
        <span class="gallery-item">
          <img class="project-img reveal" src="${webImageUrl(img, "full")}" alt="${escapeHtml(project.title)} — vue ${i + 1}" loading="${i === 0 ? "eager" : "lazy"}" />
          <span class="gallery-index">${String(i + 1).padStart(2, "0")} / ${String(project.images.length).padStart(2, "0")}</span>
        </span>`
    )
    .join("");

  const othersHtml = PROJECTS.filter((p) => p.slug !== project.slug)
    .map((p) => {
      const otherCover = pickCover(p);
      const otherImg = otherCover ? `<img src="${webImageUrl(otherCover, "card")}" alt="${escapeHtml(p.title)}" loading="lazy" />` : "";
      return `
        <a class="others-item" href="projet.html?slug=${p.slug}">
          <span class="others-thumb">${otherImg}</span>
          <span class="others-name">${escapeHtml(p.title)}</span>
        </a>`;
    })
    .join("");

  // Si un lien est fourni (page projet sur le site de l'architecte, etc.),
  // le nom de l'architecte devient cliquable plutot que d'afficher l'URL
  // brute quelque part dans le texte.
  const architecteValue = parsed.link
    ? `<a href="${escapeHtml(parsed.link)}" target="_blank" rel="noopener noreferrer">${escapeHtml(architecte)} ↗</a>`
    : escapeHtml(architecte);

  const fieldsHtml =
    (architecte
      ? `<div class="field"><span class="field-label" data-i18n-fr="Architecte" data-i18n-en="Architect">Architecte</span><span class="field-value">${architecteValue}</span></div>`
      : "") +
    (client
      ? `<div class="field"><span class="field-label" data-i18n-fr="Client" data-i18n-en="Client">Client</span><span class="field-value">${escapeHtml(client)}</span></div>`
      : "");

  const heroCover = pickCover(project);
  const heroImg = heroCover ? `<img class="project-hero-img" src="${webImageUrl(heroCover, "full")}" alt="${escapeHtml(project.title)}" />` : "";

  const filmHtml = isFilm
    ? `<section class="project-film">
        <video class="project-film-player" src="${assetUrl(project.video)}" controls preload="metadata"${heroCover ? ` poster="${webImageUrl(heroCover, "full")}"` : ""}></video>
      </section>`
    : `<section class="project-gallery">${galleryHtml}</section>`;

  container.innerHTML = `
    <header class="project-hero">
      ${heroImg}
      <div class="project-hero-overlay"></div>
      <div class="project-hero-content">
        <a class="back-link" href="index.html">&larr; <span data-i18n-fr="Retour au portfolio" data-i18n-en="Back to portfolio">Retour au portfolio</span></a>
        <p class="project-cat">${categoryLabel(project.category)}${annee ? ` · ${escapeHtml(annee)}` : ""}</p>
        <h1 class="project-title">${escapeHtml(project.title)}</h1>
      </div>
    </header>
    <section class="project-body">
      <p class="project-credit">Images / animations &copy; Groupe IMING</p>
      <p class="project-desc" data-desc></p>
      <div class="project-fields">${fieldsHtml}</div>
    </section>
    ${filmHtml}
    <section class="project-others">
      <div class="others-header">
        <p class="others-title" data-i18n-fr="Autres projets" data-i18n-en="Other projects">Autres projets</p>
        <div class="others-nav">
          <button class="others-arrow" data-others-prev aria-label="Précédent" type="button">&larr;</button>
          <button class="others-arrow" data-others-next aria-label="Suivant" type="button">&rarr;</button>
        </div>
      </div>
      <div class="others-row" data-others-row>${othersHtml}</div>
    </section>
  `;

  initOthersNav(container);
  observeReveals(container);

  const descEl = container.querySelector("[data-desc]");
  const applyDescLang = (lang) => {
    descEl.textContent = lang === "en" ? enText : frText;
  };
  const activeLangBtn = document.querySelector("[data-lang].is-active");
  applyDescLang(activeLangBtn ? activeLangBtn.getAttribute("data-lang") : "fr");
  document.querySelectorAll("[data-lang]").forEach((btn) => {
    btn.addEventListener("click", () => applyDescLang(btn.getAttribute("data-lang")));
  });
}

document.addEventListener("DOMContentLoaded", () => {
  initHero();
  initHeader();
  initGrid();
  initProjectPage();
});
