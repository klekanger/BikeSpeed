# BikeSpeed

A fullscreen iPhone speedometer for your bike, styled after 80s-car analog dashboards. Mount your phone on the handlebar, open the app, and ride — no setup, no accounts, no distractions.

![BikeSpeed mounted on a handlebar](docs/images/on-bike.webp)

## Features

- **Analog speed gauge** — a live GPS-driven needle on a 270° dial, with a configurable max speed and a red danger zone near the top, plus a digital speed readout in the center
- **Trip stats** — average speed, distance traveled, altitude, and GPS position, all updating live in a 2×2 panel; tap the speed cell to swap between average and max speed, tap the altitude cell to swap between altitude and latitude/longitude
- **Direction of travel** — an arrow plus compass letters (N, NE, E, SE, S, SW, W, NW) showing which way you're heading
- **GPS signal indicator** — a top-left glyph tinted green/yellow/red for signal quality; when the signal is too poor to trust, speed and distance freeze rather than drift on noise
- **Trip controls** — Start, Pause/Resume, Save, and Reset, so you can pause at traffic lights without losing your average, save a finished ride to your trip log, and reset cleanly for a new one
- **Trip log** — completed trips are saved with date, duration, distance, average/max speed, and a height-profile chart plotted against distance; browse past trips and delete ones you don't want to keep
- **Settings** — set your own max gauge speed, switch between metric (km/h) and imperial (mph) units, and override the app's display language independent of your device setting
- **Built for the handlebar** — runs fullscreen with the status bar and home indicator hidden, and keeps the screen from sleeping while you ride
- **English and Norwegian** — follows your iPhone's language setting automatically, or pick one explicitly in Settings

## Getting started

1. Mount your iPhone on your handlebar with a case/mount that keeps the screen visible and portrait-oriented.
2. Open BikeSpeed and allow location access when prompted — this is required for the speedometer, GPS position, and direction indicator to work.
3. Open the gear icon in the top-right corner to set your preferred max gauge speed, units (metric/imperial), and display language before you start riding.
4. Tap **Start** to begin tracking a trip. Average speed and distance begin accumulating from this point.
5. Tap **Pause** at stops (e.g. traffic lights) to keep your average speed accurate — pausing doesn't reset your stats. Tap **Resume** to continue.
6. While paused, tap **Save** to add the trip to your trip log (open it via the clock icon in the top-right corner), or **Reset** to discard it and start fresh. Reset is only available when the trip is idle or paused, so you can't accidentally lose an in-progress ride.

## Requirements

- iPhone running iOS 17.6 or later
- Location Services enabled for BikeSpeed (When In Use)
- A GPS signal — speed, direction, and position accuracy depend on GPS reception, so results may be less accurate indoors or in dense urban areas
