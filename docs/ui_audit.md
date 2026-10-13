# UI/UX audit

Written after looking at the rendered screens in `test/goldens/before/`, not
from reading the code. Every claim below is something visible in those images
or verifiable in the theme.

---

## The finding that explains everything

**There are two separate applications sharing one codebase.**

`AppRouter.createRouter` branches on `kIsWeb` and hands the web to
`WebRouter`, which renders an entirely different set of widgets:

| Mobile | Web |
| --- | --- |
| `core/authentication/screens/login_screen.dart` | `web/pages/web_login_page.dart` |
| `core/dashboard/screens/dashboard_screen.dart` | `web/pages/dashboard_page.dart` |
| `core/assets/screens/assets_screen.dart` | `web/pages/inventory_page.dart` |
| …and so on for every screen | …ten pages, ~8,000 lines |

None of the ten web pages references `AppMotion`, `AnimatedGradientBackground`
or any motion widget. **Every animation added so far exists only on mobile.**
That is why the login screen looked unchanged on web: it was unchanged.

This doubles the real surface area. Any "redesign every screen" has to be read
as "redesign every screen twice, or unify them". The audit below flags, per
item, which side it applies to.

---

## 1. Brand: the app is the wrong colour

The PSBA logo is **deep green, `#0B6B3A`** — sampled from
`assets/branding/psba_mark.png`, where it covers 44,512 of the opaque pixels.

The app's theme primary is **`#2457D6`, a blue**
(`AppColors.primary` in `core/theme/colors.dart`).

So every button, link, chip, icon tile, accent bar, selected state and focus
ring in the product is a colour the brand does not use, sitting next to a green
logo. In `login_web_desktop_light.png` the green mark sits directly above a
blue "Sign in" button; on the dashboard, a green logo tile sits above eight
cards accented in blue, purple, cyan and indigo.

**Change:** rebuild the palette from `#0B6B3A`. Green primary, a warm
secondary for emphasis, and tinted surfaces derived from the same hue.

## 2. The background reads as a grey smudge, not as colour

`login_mobile_phone_light.png` shows the Rich background over a light surface
as a dull lavender-grey haze. The cause is arithmetic, not taste: a saturated
blue at 30% alpha over a near-white surface, blurred at 15% of the short side,
desaturates to grey. It is simultaneously *too strong* (it dirties the surface)
and *too weak* (it reads as nothing).

**Change:** stop painting flat circles at high alpha. Use fewer, larger shapes
at lower alpha over a **tinted** surface rather than white, so the colour has
something to sit on. Judge it from the rendered image, not from the numbers.

## 3. Dashboard: eight boxes and nothing else

`dashboard_mobile_phone_light.png` is a greeting banner followed by eight stat
tiles, two per row, and that is the whole screen above the fold and well below
it. Specifically:

- **No charts at all.** There is no way to see the shape of the inventory —
  what is available vs assigned vs damaged — only eight separate numbers.
- **No quick actions.** Nothing to do from the screen.
- **No recent activity.** Nothing about what changed.
- **Colour is decorative, not meaningful.** Each tile has a different accent
  (blue, green, cyan, purple, indigo, red, orange, teal) with no system behind
  it. "Damaged at HO" being red is meaningful; "All Bazaars" being cyan is not.
  The result reads as a toy palette rather than a status language.
- **"All Bazaars" shows `-`** while its stream loads, next to real numbers.
  A dash and a number look equally final.
- Tiles are tall and sparse: a 24px number in a 126px box, so the screen needs
  a lot of scrolling for very little information.

**Change:** a hero header with greeting, role and date; KPI cards that are
denser and use the status palette meaningfully; a donut for status breakdown;
a bar chart for stock by location; quick actions; recent activity.

## 4. Status has no visual language

Statuses appear throughout — Available, Assigned, Under Maintenance, In
Repair, Damaged, Lost, Disposed — and there is no single mapping from status
to colour. `AppColors` has a scattering of semantic names, but a chip on the
assets list, an icon on the dashboard and a slice of a future chart have no
shared source for "what colour is Damaged".

**Change:** one status palette in the design system, used by chips, icons and
charts alike, so a colour means the same thing everywhere.

## 5. Typography is the platform default

`pubspec.yaml` declares **no fonts**. The app renders in whatever the platform
supplies — Roboto on Android, the browser default on web — so the product does
not have a typographic identity, and the same build looks different on two
devices. There is also no scale: sizes are written inline per screen
(`fontSize: 24`, `fontSize: 13.5`, `fontSize: 36`), so "big number" and "page
title" mean something slightly different on each screen.

**Change:** bundle Inter (OFL) as an asset — no runtime download — and define
one scale: page title, section title, big number, body, label.

## 6. Web login: a dark slab with one flat circle

`login_web_desktop_light.png`. The left panel is `#0F172A` hard-coded, with a
single flat blue circle bleeding off the top corner, and three feature rows in
slightly-lighter boxes. It is not wrong, but it is static and generic — the
circle is the only visual idea, it does not move, and the panel ignores the
theme entirely (identical in light and dark, which is why the light shot looks
like a dark-mode screenshot).

The right half is a form floating in empty space with no card, no elevation and
a very large amount of unused vertical room.

**Change:** keep the split, but make the left panel the brand moment — the
animated gradient, in brand green, over a themed surface — and give the right
half a proper card.

## 7. Mobile login: too much empty space

`login_mobile_phone_light.png`. Roughly the top third and bottom quarter of the
screen are empty. The card is a very low-contrast white-on-grey with a 1px
border, and the header has no logo on web-rendered goldens because the brand
mark is only in the mobile header.

**Change:** a coloured header band carrying the logo, then the form card
tucked under it, so the screen has a top and a bottom rather than a floating
middle.

## 8. Numbers are hard to scan

Big figures are `fontSize: 24, w700` with no thousands separators —
`dashboard_mobile_phone_light.png` shows `201`, `80`, `40`. At four or five
digits (total inventory value is in the millions) these will run together and
`FittedBox` will shrink them to fit, so the most important number on the
screen becomes the smallest. There is no tabular-figure setting, so columns of
numbers will not align.

**Change:** a dedicated numeric style with tabular figures and grouped
thousands, sized by importance rather than by available space.

## 9. Touch targets and density

Stat tiles are comfortably large, but the trailing `↗` affordance on each card
is a 16px icon with no padded hit area, and the app-bar actions sit at the
default 48px while the drawer button is the only thing on the left. On the web
pages the same content is rendered at phone density, so a 1440px window shows
two columns of very wide cards with large runs of empty space.

**Change:** minimum 44px targets for anything tappable; a responsive column
count rather than a fixed two.

## 10. Empty and loading states

These are already better than the rest: `AppEmptyState` and `AppSkeleton*`
exist, are shared, and now animate. The gap is that they are not used
everywhere, and the skeletons do not match the shape of the content they stand
in for (a generic block where a KPI card will appear).

**Change:** skeletons shaped like their real content, and the coloured empty
state used on every list.

---

## What will change, in order

| | Area | Change |
| --- | --- | --- |
| A1 | Design system | Brand green palette, status colours, Inter, scale, radii, shadows |
| A2 | Login (mobile + web) | Brand header / split panel, card, visible entrance |
| A3 | Dashboard (mobile + web) | Hero, KPI cards, donut, bar chart, quick actions, activity |
| B | Everything else | Per-screen, after Phase A is approved |

Business logic, providers, services, Firestore queries, security rules, the
Local AI client and routing are out of scope throughout. Every button keeps
calling exactly the function it calls today.
