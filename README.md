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

The hero keeps a world-space heading and a separate forward speed. Without input, its heading gradually straightens toward world-up. Each tap adds an angular impulse in the current corridor's diagonal direction without adding speed; repeated taps can pass the ideal angle and oversteer. Perfect pad centers boost strongly and rotate the actual heading 28% toward the next racing direction. A graze is awarded once after entering a near-wall zone and safely leaving it.

## Main tuning points

Select the `Game`, `Hero`, or `Corridor` nodes in `scenes/game.tscn`. Exported Inspector values cover flight physics, pad boost/reorientation, corridor dimensions and bend limits, grazing, and progression.

Key steering values on `Hero` are `cruise_speed`, `tap_angle_impulse_degrees`, `vertical_return_rate_degrees`, `max_heading_angle_degrees`, and `weak_corridor_follow_rate`. `Corridor` exposes `bend_transition_length`, curve sampling, bend limits, and a sharp-turn width safety bonus. `Game` exposes diminishing Perfect boost effectiveness and graze exit hysteresis.
