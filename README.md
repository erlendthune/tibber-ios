# TibberDashboard (iOS)

TibberDashboard is an iOS app that turns a phone or tablet into a live home energy monitor and control panel.

The main idea is to use a mobile device as a wall-mounted or desk dashboard that can:
- Receive real-time information from external systems
- Alert on important events
- Control connected devices directly
- Trigger actions based on live state

## What The App Does

- Shows real-time Tibber power and hour consumption metrics
- Highlights critical usage based on your configured threshold
- Supports audio alarms and Telegram alerts for important events
- Integrates with a garage camera and ML-based door-state detection
- Supports camera learn mode to collect training snapshots in Photos
- Integrates with Zaptec charger controls (pause/resume/current)
- Integrates with Philips Hue for visual alert signaling

## Why This App Exists

The goal is to make one always-available control surface for everyday home operations:
- Monitor energy usage continuously
- Be notified quickly when limits are exceeded
- Act immediately from the same screen
- Extend behavior by adding integrations over time

## Why Not Home Assistant

This project intentionally avoids a traditional Home Assistant setup.

Reasons:
- Reuse existing equipment instead of buying and maintaining more hardware
- Avoid running a dedicated backend server 24/7
- Avoid needing a separate frontend/dashboard computer
- Use an old iPhone or iPad as a complete unit

In other words, backend and frontend live in one device: install the app on an older iOS device, place it where you need it, and run your monitoring + control workflow from there.

## Core Integrations

- Tibber: live consumption and threshold monitoring
- RTSP Camera: live stream and periodic snapshot analysis
- Core ML model: garage door open/closed classification
- Telegram: recipient-based alert delivery
- Zaptec: EV charger status and controls
- Philips Hue: bridge discovery, linking, and alert flashing

## Garage Camera Workflow

1. Configure camera credentials in Settings.
2. Enable Garage Door Detection to classify snapshots.
3. Optionally enable Learn Mode and set a save interval in minutes.
4. Review saved snapshots in Photos and use them to build a better training dataset.

## Project Structure

- TibberDashboard/: app source
- TibberDashboardTests/: unit tests
- TibberDashboardUITests/: UI tests
- garagedoorclassifier.mlmodel: bundled Core ML model

## Notes

- Camera and bridge integrations depend on local network availability.
- Learn mode requires Photos permission to save snapshots.
- Some API integrations depend on external account setup and valid credentials.
