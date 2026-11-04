# Photo Mode

A photo mode for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianModManager) mod manager. It stops a mission, clears the screen of the HUD, and hands the camera and the look of the level over to a panel of controls, for pictures saved straight to the Pictures folder.

Open it with **F7** or the **PHOTO MODE** row of the pause menu, during a mission. Esc, F7 or the panel's close button leave it, and everything goes back as it was.

It needs Obsidian API 1.23.0 or later, which Obsidian installs with it. It's a client mod: it works in any lobby, and only this player sees what it changes. With other players in the lobby the game keeps running, as pausing one player's game would split it from theirs.

## Controls

| Key | What it does |
|---|---|
| W A S D | Move the camera |
| Q, E (Ctrl, Space) | Down and up; in Isometric mode, a quarter turn |
| Right mouse button | Look around |
| Mouse wheel | Field of view in Free mode, distance or zoom in the others |
| Shift, Alt | Four times faster, four times slower |
| Z, C | Roll the picture |
| P | Take a picture |
| H | Hide or show the panel |
| Arrow keys, Enter, Tab | Rows, values and tabs of the panel; the mouse works too |

A pad's sticks move and turn the camera. P, H and F7 can be changed in the Keys tab of Photo Mode in Obsidian.

## The panel

- **Camera**: Free, Orbit (circles the Helldiver, or turns by itself for a turntable view) and Isometric (a fixed angle, with a telephoto lens or no perspective at all). Move and look speed, smoothing, how far the camera can go, and staying above the ground.
- **Lens**: field of view, roll, depth of field (focused on the Helldiver or at a distance), exposure, vignette and bloom.
- **Look**: ready-made filters, the planet's color grading on or off, a color laid over the picture, fog, glow, cloud shadows and dust.
- **Light**: the time of day, blending the planet's dawn, day, dusk and night; the sun's direction, height, color and strength; shadow fill; the Helldiver's flashlight; and up to eight placed lights, each with a color, brightness, reach, a point or spot shape and shadows.
- **Scene**: pause or slow motion, a sky over the level, and the Helldivers shown or hidden.
- **Frame**: aspect ratio from 32:9 to 9:16, cut or kept with black bars, composition grids, and a caption in the game's title font.
- **Photo**: PNG or JPEG, the folder, the ship music that starts after a while in Photo Mode, and the key guide.

Every look value stays the planet's until changed; R on a row gives the planet's back.

## Pictures

Pictures go to `Pictures\Helldivers`, named by date and time, at the size of the game's window. The panel, the grid and the key guide are left out; a caption, black bars and the color over the picture stay in. The game has no screenshot call, so Photo Mode copies the window through Windows. In exclusive fullscreen the copy can come back black: borderless or windowed mode lets it through.

## Skies

The game was made to be seen from above, so past the level it draws nothing, and the picture keeps smears of old frames there. The **Fix skies** option, on by default in the mod's options in Obsidian, clears that part of the picture each frame and adds five skies (day, dawn, dusk, night and overcast) for the Sky row of the Scene tab. It changes how the game starts up, so it takes effect at the next launch.

## Building the skies

`python tools/build_sky.py` rebuilds `res/` from an installed copy of the game: the dome the engine keeps for its editor, its material, the render config with the fix, and the five skies, drawn by the script. It needs numpy and Pillow.

## Tests

`luajit tests/run.lua` runs the offline tests: the camera's movement, the look values, the overlay, opening and closing against a stand-in for the API, and the writing of the shown text.

## Credits

The sky fix follows the one found by the Third Person Camera mod for this game: clearing two more of the picture's targets in the render config's clear pass, and a sky dome built on the engine's own. The skies here are drawn by `tools/build_sky.py`.

## License

MIT
