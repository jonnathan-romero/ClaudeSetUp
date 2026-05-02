# Meaning Reference

**When to consult this:** translating a mood brief into a palette ("calm fintech", "energetic kids' app"); doing brand work where a color has to do semantic work; explaining color choices to a user who asked "why this hue, not that one"; flagging a culturally-loaded decision before shipping it ("red = up or down?", "white wedding or white funeral?"). Default posture: separate empirical findings from convention from folklore, every time.

## Contents

1. Opening thesis
2. Harmony rules with critique
3. Empirical findings worth citing
4. Industry conventions
5. Culture
6. Translating mood briefs to OKLCh
7. Red flags — when to push back
8. Sources

---

## 1. Opening thesis

Two color-emotion findings replicate cleanly across cultures, populations, and methodologies: the **warm/cool valence axis** (warm hues read more arousing, cool hues more calming) and **chroma → activation** (saturation drives perceived energy independent of hue). Treat these as design inputs. Almost everything else — "blue means trust," "yellow means happy," "green means healthy," classical hue-geometry harmony, the entire Pinterest-grade hue-to-emotion catalog — is convention, not fact. Specific hue → emotion claims have small effect sizes, fail replication often, and are dwarfed by context, brand priors, and the surrounding palette. The skill's posture: lean on the robust dimensions for generation, surface conventions as flags the user can lean into or break deliberately, and refuse to assert folklore as truth. This file's job is to keep that line drawn.

---

## 2. Harmony rules with critique

The classical wheel rules are useful as scaffolding for explanation and constrained generation, but the variable that actually carries harmony in modern displays is **L\* and C\* discipline**, not hue geometry. Schloss & Palmer (2011) showed pair harmony increases with hue *similarity*, not opposition; lightness contrast — not hue contrast — drives most of the variance. The "opposites attract" framing of complementary harmony is largely a 19th-century pigment artifact.

| Rule | Hue relation | Use case | Failure mode |
|---|---|---|---|
| Complementary | 180° opposite | High-impact accents, CTAs, sports brands | Vibrating edges (Chevreul); reads cheap at full saturation; needs one side desaturated |
| Split-complementary | base + two adjacent to complement | Softer tension, retains contrast | Muddiness when all three sit at similar L\* and C\* |
| Analogous | 3 adjacent (~30° apart) | Calm, naturalistic, in-world cohesion | Low differentiability; categorical viz fails; UI loses hierarchy |
| Triadic | 120° apart | Playful, balanced, kids' brands, illustration | Reads as kindergarten without strict 60-30-10 weighting and value separation |
| Tetradic (rectangle/square) | two complementary pairs / four 90° apart | Rich illustration, editorial, complex dashboards | Nearly impossible to balance; one pair dominates |
| Monochromatic | single hue, varied L\* and C\* | Minimalist UI, value-driven hierarchy | Needs a second channel (icon, weight, layout) to differentiate |

**The critique.** The wheel ignores lightness and chroma — which is exactly where palettes succeed or fail. Pick any hues you like; if you put them at the same L\* and the same C\* in OKLCh, they will look like a coherent palette regardless of where they sit on the wheel. Tableau 10, Material tonal palettes, IBM Carbon, Radix all rely on L\*/C\* control across hue families, not wheel geometry. The reliable construction recipe:

1. Pick hues by intent (brand, semantics, accessibility).
2. Lock all hues to a small set of L\* steps (e.g., 30, 50, 70, 90).
3. Hold C\* roughly constant within a tier (or taper deliberately).
4. *Then* worry about hue relationships.

Geometric studies confirm this: combinations following a linear pattern in the chroma-lightness plane are significantly preferred over non-linear combinations (arXiv 1709.02252). Wheel rules are decoration on top.

**Warm/cool advance/recede.** Real but weak. Long-wavelength hues advance against neutral backgrounds; short wavelengths recede. But **value dominates temperature** — a dark cool color advances against a pale warm one. Useful default for low-contrast scenes; mostly convention in high-contrast UI.

**60-30-10.** Works because it imposes hierarchy, not because the ratios are magical. Any (large, medium, small) split with strong proportional asymmetry will read as composed. Ignore for categorical dataviz (you want roughly equal perceptual weight) or three peer brand colors that must coexist as equals.

---

## 3. Empirical findings worth citing

**Palmer & Schloss — Ecological Valence Theory (2010, *PNAS*).** Adult color preferences track the weighted average affective valence of objects associated with each color. Blues poll high partly because clear water and clear skies poll high; yellow-greens poll low partly because vomit and rot poll low. Partially replicated cross-culturally (Taylor & Franklin 2012 UK; Yokosawa et al. 2016 Japan/US contrast). The mechanism (preference tracks ecological associations) holds; the specific rankings are population-dependent. Treat EVT as the best mechanistic theory available, not a lookup table.

**Schloss & Palmer (2011).** Pair harmony increases with hue *similarity*, not opposition. People agree on harmony far more than on preference. Lightness contrast drives a large share of the variance. This is the single most-cited empirical finding against the classical complementary rule.

**Jonauskaite ISCE — International Survey of Colour and Emotion (2020, *Psychological Science*).** 4,598 participants across 30 nations, 12 colour terms × 20 emotion terms. Findings the skill can rely on: there is a *cross-cultural common core* (red ↔ love and anger; black ↔ sadness and fear; yellow ↔ joy; pink ↔ love), but country-by-country variance is substantial and organized by linguistic family and geographic latitude (yellow-joy weakens in rainy countries). Hue → emotion is **not** a fixed function. The 2019 follow-up specifically links yellow's joy association to local sunshine.

**Elliot & Maier (2014, *Annual Review of Psychology*).** The most-cited synthesis. Honest conclusions: (a) the field is young and undersized; (b) red/achievement and red/attraction effects are real but context-bound; (c) most demonstrations are single-lab and need replication. The most robust generalization: **the warm/cool affective dimension** holds across cultures and methodologies.

**Valdez & Mehrabian (1994, *JEP:General*).** Saturation/chroma drives perceived activation/arousal more than hue. Lightness drives perceived pleasantness. One of the strongest findings in the literature; underused in design conversations.

**Memory color (Hansen et al. 2006, *Nature Neuroscience*).** A gray banana on a neutral background appears slightly yellow — observers must subtract yellow to see it as truly achromatic. Implication: palettes that use hyper-prototypical hues for canonical referents (sky, grass, blood, gold) feel "right" even when objectively less accurate.

**What does *not* replicate.** Hill & Barton's "red shirts win" sports finding (failed re-analyses: Rowe 2005, Hagemann 2008, Krenn 2014). Elliot & Niesta's "red enhances attractiveness" (Lehmann et al. 2018 large-scale replication, near-null). Baker-Miller pink "calms inmates." Mehta & Zhu's "blue boosts creativity, red boosts detail" — partial replication, highly task- and luminance-dependent. If a user cites these, point at the replication failures.

---

## 4. Industry conventions

These are conventions, not laws. Knowing them lets the user choose with intent — including when to break them.

**Fintech / banking — blue and green.** Heavy bias toward navy, mid-blue, and deep green (Chase, Citi, AmEx, Stripe, Plaid). The convention exists because blue scores high on "trust" in Heller and follow-ups (small effect, but consistent direction), and green reads as money in US contexts. The trust effect is convention, not fact — the actual driver is category conformity: every fintech is blue, so blue reads as fintech. Breaking the convention works when the brand stance is "we are not your father's bank" — Monzo coral, Revolut black, N26 minimal mono.

**Healthcare — calm + clean + alarm-system standard.** Clean blues, calming greens; saturated red reserved for genuine emergency states. The convention exists for two reasons. First, hospital signage history. Second — load-bearing — the IEC 60601-1-8 alarm-color standard for medical devices reserves red for high-priority alarms, yellow for medium-priority, cyan/white for low-priority and information. Red on a non-alarm UI element in a clinical context is a real safety/regulatory concern, not just an aesthetic choice. Wellness / consumer-health brands (Calm, Headspace, warm pastels) sit outside the clinical context and break the convention safely.

**Kids' products — high chroma, primary-adjacent.** Children under ~5 demonstrably prefer high-saturation primaries (Franklin et al., 2010, *Cognition*). The convention exists because the audience preference is real and developmentally grounded, not aesthetic guesswork. Breaking it works for "elevated kids" brands targeting parents (Maisonette, Hatch) — those palettes are designed for the buyer, not the user.

**Luxury — restrained chroma, deep neutrals.** Black, ivory, deep burgundy, navy, metallics. The convention encodes "I do not need to shout" — restraint *is* the signal, low chroma is how restraint reads on a screen. Heller's data has black dominant for "elegant" and "luxurious." Breaking it is genuinely rare and usually a deliberate generational reposition (Bottega green, Loewe acid green) where the loud color *is* the statement.

**Editorial — high-contrast neutrals + single accent.** Off-white background, near-black text, one accent. The constraint is print legibility on long-form text — the convention is downstream of typography, not aesthetics. Breaking it is a magazine-redesign moment (Bloomberg Businessweek under Richard Turley is the canonical example).

**Tech B2B — the "blue everything" critique.** Default SaaS palette is near-identical (cobalt primary, slate grays, white background). Exists because blue is safe, accessible-by-default, and reads as "software" through pure category conformity. The category is now visually undifferentiated; breaking it is straightforward and often correct.

---

## 5. Culture

The well-supported finding from cross-cultural research is that *basic color terms* and *broad valence* (light = good / dark = bad) are stable across cultures (Berlin & Kay 1969; World Color Survey). What is **not** well-supported is the Pinterest-grade "yellow means X in country Y." Specific hue-to-meaning mappings are weak, context-dependent, and frequently contradicted by within-culture variance.

Documented cases worth flagging:

- **Red.** In Mainland China, Hong Kong, and much of East Asia, red is a prosperity / celebration color (wedding dress, hongbao, Lunar New Year). In Western financial UI, red is a *loss* color — and Bloomberg-style green-up/red-down conventions are *reversed* on Chinese exchanges (red = up). Real risk for any bilingual finance product.
- **White.** Western weddings vs. traditional mourning / funeral color in parts of South and East Asia (India, China, Korea). Durable; worth the skill flagging.
- **Green.** "Environment / sustainability" in Western markets vs. "US currency / money" vs. religiously charged in much of the Islamic world (used in many national flags, the Saudi flag, historically associated with Islam).
- **Purple.** Mourning in Brazil and parts of Catholic Europe; royalty in Western Europe; weak signal in much of East Asia.

Roberson, Davies & Davidoff (2000, 2005) on the Himba and Berinmo: categorical *perception* tracks language. Color category boundaries the skill might assume (the blue/green line) are not universal.

**Anti-essentialism guardrails:**

1. "Chinese users prefer red" flattens 1.4 billion people. The honest claim is "in Chinese cultural contexts, red carries celebratory connotations that are absent or reversed in some Western contexts."
2. Culture is one input among many. Brand position, product category, competitive set, and accessibility usually outrank cultural connotation. A Chinese fintech may still pick blue because every fintech is blue and the trust association outweighs the celebratory red default.
3. When the skill does not know, it should say so. "I don't have strong evidence about X in Y market — worth checking with a local designer" is a correct answer.

Aslam (2006, *Journal of Marketing Communications*) is the standard cross-cultural marketing color review and even Aslam concedes effects are modulated by product category, age, and education. Treat documented cases as defaults to check against, not universal laws.

---

## 6. Translating mood briefs to OKLCh

The translation move is to extract OKLCh-shaped constraints from a mood phrase. These bands are starting points for generation, not specifications — validate against the user's actual brief and any reference images.

| Brief axis | Direction | OKLCh constraint |
|---|---|---|
| calm | low activation | C ≤ 0.06; avoid step-9 chroma peaks |
| energetic | high activation | C ≥ 0.14 at step 9; allow saturated accents |
| warm | hue family | H ≈ 20–80 (red-orange-yellow arc) |
| cool | hue family | H ≈ 200–280 (cyan-blue-violet arc) |
| luxury | restrained + heavy | C ≤ 0.05 across the palette; deep neutral spine (one hue at L ≈ 0.18–0.25); black, ivory, metallic accents |
| playful | varied chroma | C variance high across the palette; mix C ≈ 0.04 neutrals with C ≈ 0.16+ accents; multiple hue families allowed |
| trustworthy / corporate | category conformity | H ≈ 220–260 (navy / mid-blue) at moderate C ≈ 0.08–0.14 — flag as convention, not fact (see §4 fintech) |
| natural / organic | analogous + earthy | H within a 60° window centered on 80–120 (green/yellow-green) or 30–60 (terracotta); C ≤ 0.08 |
| clinical / clean | high-L, low-C, blue-green | L ≥ 0.95 backgrounds; C ≤ 0.04 neutrals; one mid-L blue-green accent (H ≈ 180–220); reserve red for IEC 60601-1-8 alarm semantics |
| editorial | neutral + single accent | near-black + off-white spine; one accent at C ≈ 0.10–0.16 in any hue family |

**Caveats.** These are starting zones, not laws. Over-saturation is the more common amateur mistake — when in doubt, drop chroma. The mood phrase is an aesthetic gesture, not a specification: propose the OKLCh translation as a hypothesis, validate against any reference images by sampling actual pixels, and ask the user whether the hypothesis matches what they had in mind.

Worked examples:

- "Calm Scandinavian fintech" → low C ≤ 0.06; high-L background L ≥ 0.95; one mid-L accent in blue-green arc H ≈ 200–220; strong neutral spine.
- "Warm 70s editorial" → mid-L cream background (L ≈ 0.92, H ≈ 80, small C); accents in burnt orange / mustard / avocado (H ≈ 40–110, C ≈ 0.10–0.14); avoid pure cool grays.

---

## 7. Red flags — when to push back

Some briefs encode untested assumptions. Push back surgically; don't lecture.

- **"Make it look trustworthy."** Trust is not a hue. Ask what trust signals the user actually means — category conformity (other fintechs are blue), restraint (low chroma reads as "not flashy"), accessibility (high contrast reads as "this product respects me"), or specific claims (lock icons, security copy, certification badges). Color does a small share of the work; the rest is information design.
- **"Yellow always means happy."** Not universally. The Jonauskaite ISCE common core has yellow ↔ joy as a cross-cultural prior, but the 2019 follow-up shows the strength varies with local sunshine and the within-culture variance is substantial. Surface as convention, propose the warm-hue + high-chroma move that drives the "happy" reading more reliably than hue-identity does.
- **"Red = danger / green = go."** Inherited from traffic signaling, reinforced by IEC 60601-1-8 in clinical UI. In Chinese financial UI it inverts (red = up). Always ask about market and context before locking status colors.
- **"This palette feels off — give me different colors."** Often the issue is L\*/C\* discipline, not hue. Check whether all hues sit at coherent L\* steps and matched chroma envelopes before swapping hues. Hue swaps without L\*/C\* discipline rarely fix the underlying problem.
- **"Make it pop / make it more vibrant."** Frequently means "raise chroma" but sometimes means "raise lightness contrast." Diagnose which channel is undercooked before pushing chroma toward gamut limits.
- **"Use the colors of [country flag] because we're targeting [country]."** Conflates national identity with consumer preference. Usually wrong — local fintechs in that market still pick the global fintech blue, because category conformity outranks flag association. Ask whether the user wants nationalism as a brand stance or just market relevance.
- **Single-study color-mood claims** ("blue makes you smarter," "pink calms inmates," "red shirts win"). Treat as folklore; cite the replication failures (§3) if the user insists.

---

## 8. Sources

- Palmer & Schloss, 2010, *PNAS* 107(19): 8877–8882. https://doi.org/10.1073/pnas.0906172107
- Schloss & Palmer, 2011, *Attention, Perception, & Psychophysics*. https://pmc.ncbi.nlm.nih.gov/articles/PMC3037488/
- Jonauskaite et al., 2020, *Psychological Science* 31(10): 1245–1260. https://doi.org/10.1177/0956797620948810
- Elliot & Maier, 2014, *Annual Review of Psychology* 65: 95–120. https://doi.org/10.1146/annurev-psych-010213-115035
- Valdez & Mehrabian, 1994, *JEP: General* 123(4): 394–409. https://doi.org/10.1037/0096-3445.123.4.394
- Aslam, 2006, *Journal of Marketing Communications*. https://doi.org/10.1080/13527260500247827
- IEC 60601-1-8 (medical alarm color standard). https://webstore.iec.ch/publication/2599
- Hansen, Olkkonen, Walter & Gegenfurtner, 2006, *Nature Neuroscience* 9: 1367–1368. https://doi.org/10.1038/nn1794
