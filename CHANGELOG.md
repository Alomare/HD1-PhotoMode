# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## 1.6.4

- A game stopped for pictures runs again when another player joins, as with other players in the lobby from the start.
- Fixed: Photo Mode stays closed with Third Person Camera installed and says so, as that mod keeps the camera.

## 1.6.3

- W A S D and the other camera keys work again after a click on a slider row. They stopped while the row waited for a typed number.

## 1.6.2

- Added a picture for the mod in Obsidian.

## 1.6.1

- Changed depth of field to on when Photo Mode opens, with autofocus on the Helldiver. The Lens reset turns depth of field back on.
- Changed the panel to open at 540 by 540 instead of 540 by 360. A panel already moved or resized stays in place until Reset panel position.

## 1.6.0

- Changed the tabs to Camera (with game speed), Lens, Look (with exposure, vignette, bloom and grain), Light (with the sky), Helldiver, Capture (frame, caption and file) and Settings, each with a title and a reset button for that tab.
- Added Helldiver parts that show or hide one by one: helmet, heavy armour, boots, weapon in hand, other weapons and backpack.
- Fixed poses that stayed on: a new pose ends the one before, As it was ends any pose, and closing Photo Mode ends the pose too, so at ease and the radio no longer stay.
- Fixed the place and turn of the Helldiver, which now hold, and sinking the Helldiver into the ground no longer kills the Helldiver.
- Removed the lens flare, the light leak and the Helldiver flashlight, which only night armour has.
- Changed grain to follow the slider in steps of 0.01, so low values work.
- Changed Cinematic, Vivid and Sunlit to nudge the exposure and bloom of the planet a little instead of replacing them.
- Added Music level back, at -6 dB by default.
- Fixed Remove all lights, which left the handles behind, and a new light now comes selected.
- Needs Obsidian API 1.29.0.

## 1.5.0

- Changed film grain to a texture of Gaussian noise tiled over the screen, with a new spot every frame and three fields for color grain. The picture keeps the same brightness.

## 1.4.0

- Fixed poses, and a moved Helldiver now stays in place.
- Added a Cape row.
- Fixed hiding the Helldiver, which showed the stratagem radio.
- Changed Fog to a thickness of the planet fog, and a sky no longer clears the fog.
- Changed filters to leave the sun and the time of day alone.
- Added Export and Settings tabs.
- Changed music to on or off only, the panel to 70% size and sky brightness to 1 by default.
- Changed grain and light leak to smoother, and the flare no longer needs a clear line to the sun.
- Removed Glow.
- Changed the help lines to new wording.
- Changed far cameras to keep detailed models.

## 1.3.0

- Added a Film tab with grain, lens flare and light leak.
- Added a Helldiver tab: visibility, poses from the game animations, size, place and turn.
- Changed the tab icons to new ones drawn from shapes.
- Changed the music to the exploring track of the mission.
- Changed the sky to open matching the time of day.
- Fixed Hide Helldivers, Sky brightness, lights drifting off the markers, and light numbers after a wipe.

## 1.2.0

- Added Photo Mode on the ship, from F7 or the pause menu. Lights, skies, the time of day, screen dust and cloud shadows come from mission content, so they are greyed out there, with the reason in the help line.
- Changed the ship music to pause and come back after the delay.

## 1.1.0

- Fixed mouse look, which was upside down. The cursor hides while looking.
- Changed the ship music to keep playing through the pause.
- Fixed the fog with a sky showing, which now reaches past the dome. A sky that cannot show writes the reason to the log.
- Changed the screen dust layer to off by default.
- Added markers with handles to drag placed lights, a three-point rig that lights the Helldiver, focus on the point under the cursor with a double click, and lens presets from 14 to 200 mm.
- Changed the panel to open at the bottom right and to move, resize and scale, with icon tabs, a reset button and plainer labels.
- Changed the key guide to a tidy box.

## 1.0.0

- Added Photo Mode: stops a mission and clears the screen for pictures. Opens with F7 or the PHOTO MODE row of the pause menu.
- Added a free, orbiting or isometric camera, with lens and look controls.
- Added the time of day, the sun, placed lights, and a sky over the level with the Fix skies option.
- Added pictures saved to `Pictures\Helldivers`.
- Needs Obsidian API 1.23.0.
