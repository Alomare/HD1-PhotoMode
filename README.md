# Photo Mode

A photo mode for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianModManager) mod manager. It stops a mission, clears the screen of the HUD, and hands the camera and the look of the level over to a panel of controls, for pictures saved straight to the Pictures folder.

Open it with **F7** or the **PHOTO MODE** row of the pause menu, during a mission or on the ship. On the ship, lights, skies, the time of day, screen dust and cloud shadows are greyed out: they come from a mission's content. Esc, F7 or the panel's close button leave it, and everything goes back as it was. Photo Mode does not open while Third Person Camera is installed, as that mod keeps the camera.

It needs Obsidian API 1.29.0 or later, which Obsidian installs with it, and 1.29.2 for the camera keys to keep working while a number is typed into a row. Photo Mode is a client mod: it works in any lobby, and only this player sees what it changes. With other players in the lobby, or once one joins, the game keeps running, as pausing one player's game would split it from theirs.

## Controls

| Key | What it does |
|---|---|
| W A S D | Move the camera |
| Q, E (Ctrl, Space) | Down and up; in Isometric mode, a quarter turn |
| Right mouse button | Look around |
| Mouse wheel | Field of view in Free mode, distance or zoom in the others |
| Shift, Alt | Four times faster, four times slower |
| Z, C | Roll the picture |
| Left mouse button, twice | Focus on the point under the cursor |
| Left mouse button on a light | Select the light; drag the colored handles to move it |
| P | Take a picture |
| H | Hide or show the panel |
| Arrow keys, Enter, Tab | Rows, values and tabs of the panel; the mouse works too |

The cursor hides while the right mouse button turns the camera. A pad's sticks move and turn the camera. P, H and F7 can be changed in the Keys tab of Photo Mode in Obsidian.

## The panel

The panel opens square at the bottom right. The title bar moves it, the corner grip resizes it, and the line above the help text resizes the help area. Each tab shows the tab's name at the top, with a reset button beside it that puts that tab's settings back; the reset button in the title bar puts back every tab's settings. Placed lights stay either way.

- **Camera**: game speed (paused, slow motion or running), a camera lock, Free, Orbit (circles the Helldiver, or turns by itself for a turntable view) and Isometric (a fixed angle, with a telephoto lens or no perspective at all). Move and look speed, smoothing, how far the camera can go, and staying above the ground.
- **Lens**: focal length presets from 14 to 200 mm, field of view, roll, and depth of field, on from the start and focused on the Helldiver, or at a distance.
- **Look**: ready-made filters, exposure, vignette and bloom, the planet's color grading on or off, a color laid over the picture, fog thickness from none to three times the planet's, fog color, cloud shadows, the screen dust layer (off by default: the game draws it flat over the screen for the top-down view), and film grain in mono or color. Filters nudge the planet's exposure and bloom by a little rather than replacing them, and leave the sun and the time alone, except the five that set a sun. The game's shaders have no grain, so the grain is a texture of Gaussian noise drawn over the picture, moving every frame, and photos keep it.
- **Light**: the time of day, blending the planet's dawn, day, dusk and night; the sun's direction, height, color and strength; shadow fill; a sky over the level, matching the time of day from the start; a three-point lighting rig around the Helldiver, and up to eight placed lights, each with a color, brightness, range, a point or spot shape and shadows. Placed lights show as markers in the picture, left out of photos, and a new light comes selected.
- **Helldiver**: the Helldivers shown or hidden; the cape, helmet, heavy armour, boots, the weapon in hand, the other weapons and the backpack, each shown or hidden; a pose from the game's own animations (salute, aiming, stratagem input, signals, sitting, downed and more) blended in by letting the game run for a moment; and the Helldiver's size, place and turn. A new pose ends the one before, and As it was ends any pose. The place holds while the game runs, and the Helldiver can sink into the ground without falling out of the level. The cape is cloth and doesn't follow a change of size or place.
- **Capture**: take a photo; aspect ratio from 32:9 to 9:16, cut or kept with black bars, composition grids; a caption in the game's title font; PNG or JPEG and the folder.
- **Settings**: the music that starts a few seconds into Photo Mode (the mission's exploring track at the Music level, -6 dB by default, or the ship's own music), the controls overlay, and the panel's opacity and scale.

Every look value stays the planet's until changed; R on a row gives the planet's back. Closing Photo Mode puts the Helldiver, the pose and every part back as they were.

## Pictures

Pictures go to `Pictures\Helldivers`, named by date and time, at the size of the game's window in screen pixels, whatever the display scaling. The panel, the grid and the key guide are left out; a caption, black bars and the color over the picture stay in. The game has no screenshot call, so Photo Mode copies the window through Windows. In exclusive fullscreen the copy can come back black: borderless or windowed mode lets it through.

## Skies

The game was made to be seen from above, so past the level it draws nothing, and the picture keeps smears of old frames there. The **Fix skies** option, on by default in the mod's options in Obsidian, clears that part of the picture each frame and adds five skies (day, dawn, dusk, night and overcast) for the Sky row of the Light tab. The planet's fog covers them as it covers the level; Fog on the Look tab thins it. It changes how the game starts up, so it takes effect at the next launch.

## Building the grain

`python tools/build_grain.py` rebuilds `res/grain.texture` and `res/grain.material`: four tiles of Gaussian noise that wrap at their edges, in the alpha of a white texture, with the game's font material, which tints the texture as the game draws it. It needs numpy and Pillow.

## Building the skies

`python tools/build_sky.py` rebuilds `res/` from an installed copy of the game: the sky dome from the engine's editor and the material on it, the render config with the fix, and the five skies, drawn by the script. It needs numpy and Pillow.

## Tests

`luajit tests/run.lua` runs the offline tests: the camera's movement, the look values, the overlay and the grain, the Helldiver's place, parts and poses, the tab icons, opening and closing against a stand-in for the API, and the writing of the shown text.

## Credits

The sky fix follows the one found by the Third Person Camera mod for this game: clearing two more of the picture's targets in the render config's clear pass, and a sky dome built on the engine's own. The skies here are drawn by `tools/build_sky.py`.

## License

MIT
