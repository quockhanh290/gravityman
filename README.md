# Tapline — one-tap diagonal flight prototype

A small Godot 4.x prototype focused on one question: does repeated tapping to correct an inertial flight path feel good at escalating speed?

## Run

Open `project.godot` in Godot 4.x and press **F6/F5**, or run:

```powershell
godot --path .
```

## Controls

- **Space / mouse click / screen tap:** apply the same small correction impulse
- **R:** restart
- **F3:** debug overlay and geometry
- **1:** toggle 50% speed
- **2:** toggle death
- **3 / 4:** force low / high speed

The hero keeps its momentum. Taps add velocity toward the upcoming corridor direction; they do not set position or snap the trajectory. Perfect pad centers boost strongly and rotate velocity 28% toward the next racing direction. Edge and normal hits provide less help. Near-wall flight awards escalating graze points.

## Main tuning points

Select the `Game`, `Hero`, or `Corridor` nodes in `scenes/game.tscn`. Exported Inspector values cover flight physics, pad boost/reorientation, corridor dimensions and bend limits, grazing, and progression.
