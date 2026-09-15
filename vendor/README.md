# Data sources (vendored at deploy time, see below — nothing committed that is huge)
#
# Shapes: Natural Earth 50m Admin-0 (public domain)
#   - You (not the agent) run: `bin/rails shapes:build`
#   - Downloads to vendor/geo/ne_50m_admin_0_countries.geojson (ignored by git)
#     and builds app/assets/images/shapes/<iso2>.svg per country.
#
# Flags: lipis/flag-icons (MIT) — https://github.com/lipis/flag-icons
#   - You run the snippet from DEPLOY_NOTES (copies only the ~197 needed SVGs
#     into app/assets/images/flags/<iso2>.svg).
#   - Kosovo (XK) has no official ISO flag in flag-icons; the seed still works,
#     the helper shows a placeholder until you drop vendor xk.svg manually.
