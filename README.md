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

The hero keeps its momentum and a separate forward speed. Natural lateral drift continuously builds toward one wall; every tap applies an opposite corridor-local steering impulse without adding speed. Too few taps under-correct, while rapid tapping accumulates oversteer into the opposite wall. Perfect pad centers boost strongly and rotate velocity 28% toward the next racing direction. Edge and normal hits provide less help. A graze is awarded once after entering a near-wall zone and safely leaving it.

## Main tuning points

Select the `Game`, `Hero`, or `Corridor` nodes in `scenes/game.tscn`. Exported Inspector values cover flight physics, pad boost/reorientation, corridor dimensions and bend limits, grazing, and progression.

Key steering values on `Hero` are `cruise_speed`, `tap_steering_impulse`, `natural_drift_acceleration`, `steering_damping`, `max_lateral_velocity`, and `trajectory_follow_rate`. `Corridor` exposes `bend_transition_length`, curve sampling, bend limits, and a sharp-turn width safety bonus. `Game` exposes diminishing Perfect boost effectiveness and graze exit hysteresis.
