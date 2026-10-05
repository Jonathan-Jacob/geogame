# Data sources (vendored at deploy time, see below — nothing committed that is huge)
#
# Shapes: Natural Earth Admin-0 (public domain)
#   - You (not the agent) run: `bin/rails shapes:build`
#   - Downloads vendor/geo/ne_50m_admin_0_countries.geojson, ne_10m for micro-states,
#     and geoBoundaries ADM0 for ultra-small countries (all under vendor/geo/, gitignored);
#     builds
#     app/assets/images/shapes/<iso2>.svg per country.
#
# Flags: lipis/flag-icons (MIT) — https://github.com/lipis/flag-icons
#   - You run the snippet from DEPLOY_NOTES (copies only the ~197 needed SVGs
#     into app/assets/images/flags/<iso2>.svg).
#   - Kosovo (XK) has no official ISO flag in flag-icons; the seed still works,
#     the helper shows a placeholder until you drop vendor xk.svg manually.
