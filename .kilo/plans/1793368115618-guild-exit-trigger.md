# Plan: Fix NaN vector warnings and mobile gray screen

## Problem
`area.gd` computes `bg_scale = max(view.y / tex_size.y, view.x / tex_size.x)`. On mobile, the viewport can report `(0, 0)` during early `_ready`, making `bg_scale = 0`. This cascades into zero ground range, NaN `_feet_y`, and `Vector2 cannot be normalized` warnings in `is_blocked`/`_resolve_obstacles`, causing the camera to look at empty space (gray screen).

## Fix
In `scripts/areas/area.gd` `_layout_background()`:
- Guard against zero viewport: if `view.x <= 0` or `view.y <= 0`, return early (or defer layout).
- Clamp `bg_scale` to at least `1.0`: `maxf(1.0, maxf(view.y / tex_size.y, view.x / tex_size.x))`.
- Ensure `ground_near_px > ground_far_px` (swap if needed) to avoid zero division in `depth_ratio()`.

Also reset guild scene ground values to safe image-space bounds (already 100/650).

## Validation
- Run headless tests.
- Load guild scene on mobile-sized viewport and confirm no NaN warnings.
