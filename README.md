# Ricochet Protocol · Woodland Campaign

A third-person 3D shield arena in a forest clearing. Return raider shots, use powers, and beat the Warden on level 100. The campaign is single-player against AI bots.

## Play

Open `project.godot` in Godot 4.6 or newer and press F5. Click Start or press Enter.

| Control | Action |
| --- | --- |
| WASD or arrows | Move relative to the camera |
| Mouse | Look and aim with the center crosshair |
| Left click or Space | Open the parry window |
| 1 / 2 / 3 | Equip a shield |
| Q | Use your charged shield power |
| H | Toggle aim assist |
| Esc | Pause or resume |
| M | Toggle sound |
| N at title | Start from level 1 |

Aim at a raider and click as a round closes in. Returned rounds charge your power meter. Perfect returns hit harder. Heavy shots deal splash damage when returned.

| Shield | Unlock | Power |
| --- | --- | --- |
| Guardian | Level 1 | Aegis heals and holds the shield open briefly |
| Swift | Level 5 | Dash moves quickly and grants brief invulnerability |
| Nova | Level 12 | Shockwave returns nearby incoming rounds |

Shield rank improves every ten campaign levels. Checkpoints save automatically every five cleared levels, with an extra checkpoint at the final boss. Sunlit and moonlit chapters alternate as you progress.

## Web export

With matching Godot export templates installed, export the Web preset to `index.html`. ZIP the exported files with `index.html` at the root for itch.io, then mark the build as playable in the browser. The Compatibility build uses single-threaded WebAssembly.
