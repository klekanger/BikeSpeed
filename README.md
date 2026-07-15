# BikeSpeed

A fullscreen iPhone speedometer for your bike, styled after 80s-car analog dashboards. Mount your phone on the handlebar, open the app, and ride — no setup, no accounts, no distractions.

![BikeSpeed mounted on a handlebar](docs/images/on-bike.webp)

## Features

- **Analog speed gauge** — a live GPS-driven needle on a 270° dial, with a configurable max speed and a red danger zone near the top, plus a digital speed readout in the center
- **Trip stats** — average speed, max speed, distance, duration, altitude, climb, and GPS position, all updating live in a 2×2 panel; tap or swipe a cell to page through its readouts (speed cell: average ↔ max; distance cell: distance ↔ duration; altitude cell: altitude ↔ climb ↔ position)
- **Auto-pause** — distance and time pause automatically when you stop and resume the moment you move off, so your average speed doesn't sag at every red light; on by default, and switchable in Settings
- **Elevation & gradient** — total climb over the ride and a live gradient percentage, measured by the barometer for accuracy where available and by GPS otherwise
- **Direction of travel** — an arrow plus compass letters (N, NE, E, SE, S, SW, W, NW) showing which way you're heading, with the name of the street you're currently on below it; the arrow stays live at a standstill by switching to the compass when GPS course goes quiet
- **Route map & GPX export** — every ride records its track; open a saved trip to see it drawn on a map, and export it as a GPX file to share with Strava, Komoot, or any other app
- **GPS signal indicator** — a top-left glyph tinted green/yellow/red for signal quality; when the signal is too poor to trust, speed and distance freeze rather than drift on noise
- **Trip controls** — Start, Pause/Resume, Save, and Reset, so you can pause a ride, save a finished one to your trip log, and reset cleanly for a new one
- **Background recording** — a trip keeps recording when the screen locks or you switch apps, so you can pocket the phone mid-ride without losing the trip
- **Trip log** — completed trips are saved with date, duration, distance, average/max speed, total ascent/descent, a route map, and a height-profile chart plotted against distance, above your lifetime totals and personal bests (longest ride, fastest average, top speed, biggest climb); browse past trips and delete ones you don't want to keep
- **Settings** — set your own max gauge speed, switch between metric (km/h) and imperial (mph) units, toggle auto-pause, and override the app's display language independent of your device setting
- **Built for the handlebar** — runs fullscreen with the home indicator hidden, and keeps the screen from sleeping while you ride
- **English and Norwegian** — follows your iPhone's language setting automatically, or pick one explicitly in Settings

## Getting started

1. Mount your iPhone on your handlebar with a case/mount that keeps the screen visible and portrait-oriented.
2. Open BikeSpeed and allow location access when prompted — this is required for the speedometer, GPS position, and direction indicator to work. Allow Motion & Fitness too if you want barometer-accurate climb figures; without it, climb still works from GPS.
3. Open the gear icon in the top-right corner to set your preferred max gauge speed, units (metric/imperial), auto-pause, and display language before you start riding.
4. Tap **Start** to begin tracking a trip. Average speed, distance, and climb begin accumulating from this point, and recording continues even if the screen locks.
5. Stop at a light and the trip pauses itself (auto-pause), resuming when you ride on, so your average speed stays accurate — no stats are reset. You can also tap **Pause** to stop manually, and **Resume** to continue.
6. When you're done, tap **Pause/Stop** and then **Save** to add the trip to your trip log (open it via the clock icon in the top-right corner), or **Reset** to discard it and start fresh. Reset is only available once the trip is manually paused, so you can't accidentally lose an in-progress ride.

## Requirements

- iPhone running iOS 18.0 or later
- Location Services enabled for BikeSpeed (When In Use is sufficient; recording continues in the background while a trip is running)
- Optional: Motion & Fitness access, for barometer-based climb and gradient — without it, climb falls back to GPS altitude
- A GPS signal — speed, direction, and position accuracy depend on GPS reception, so results may be less accurate indoors or in dense urban areas

## Privacy

BikeSpeed has no accounts, no analytics, and no tracking, and it does not collect your data or share it with anyone. Your location is used only to drive what you see on screen, and your trips are stored on your device — in the app's own storage, which is removed if you delete the app.

The one thing that leaves your phone on its own is a reverse-geocoding lookup: to show the name of the street you're on, BikeSpeed asks Apple's mapping service what street a coordinate corresponds to, using Apple's built-in MapKit/Core Location APIs. That lookup sends the coordinate to Apple, subject to [Apple's privacy policy](https://www.apple.com/legal/privacy/), and happens only occasionally as you move between streets, not continuously. Nothing else — speed, distance, altitude, or your trip log — is ever sent off the device automatically. If you have no network connection, the street name is simply left blank and the rest of the app works as usual.

The one exception is entirely your choice: when you tap **Export GPX** on a saved trip, BikeSpeed hands that ride's track to the share sheet so you can send it to another app or service. That only ever happens when you ask for it, with the trip you picked, going where you send it.
