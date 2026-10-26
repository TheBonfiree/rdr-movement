# RDRMovement

An over-the-shoulder camera and weighted movement for Roblox, in the style of Red Dead Redemption 2. It needs R15 avatars.

## Install in any place

1. Copy `ReplicatedStorage.RDRMovement` (this folder) into the game's ReplicatedStorage.
2. Copy `StarterPlayer.StarterPlayerScripts.RDRClient` into StarterPlayerScripts.
3. In StarterPlayer, set these three properties:
   - `DevComputerMovementMode` = Scriptable
   - `DevTouchMovementMode` = Scriptable
   - `EnableMouseLockOption` = false
4. In Game Settings > Avatar, set the avatar type to **R15**.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Move | WASD | Left stick (tilt picks walk or jog) | Drag in the lower left |
| Look | Mouse | Right stick | Drag anywhere else |
| Sprint | Hold Shift | Click L3 (toggle) | Run button (toggle) |
| Walk toggle | Caps Lock (a WALK tag shows while on) | D-pad down | - |
| Aim | Hold right mouse | Hold L2 | Aim button (toggle) |
| Swap shoulder | Q | Click R3 | Swap button |
| Jump | Space | A | Jump button |

## Custom animations

1. Animate in `Desktop\RDR-Movement\blender\R15_AnimRig.blend`, then export from the N panel > **R15 Anim** tab. That writes `exports\<action name>.rbxmx`.
2. In Studio, right-click `Workspace.R15AnimRig.AnimSaves` > **Insert from File...** and pick the `.rbxmx`.
3. Open the Animation Editor, select `R15AnimRig`, load the animation from the list, and **Publish to Roblox**. Copy the ID.
4. Paste the ID into the matching slot in `Config.Animations` (idle, walk, run, jump, fall, climb).

For walk and run, set `Config.Anim.WalkNativeSpeed` / `RunNativeSpeed` to the speed (studs per second) your cycle was animated for. That keeps the feet from sliding.

## Tuning

All feel values live in the `Config` module: speeds, acceleration and deceleration times, turn rates, pivot angle, camera offsets, FOV, lean amounts and foot IK.

Set `Debug = true` to mirror the live gear, speed and input onto LocalPlayer attributes.

## Modules

| Module | Job |
|---|---|
| `Spring` | Critically damped easing for numbers and Vector3s. |
| `Input` | Keyboard, gamepad and touch input, with its own thumbstick and jump. |
| `Locomotion` | Eased speed, limited turn rate, pivot turns, turn-in-place and strafing while aiming. |
| `AnimBlender` | Replaces the Animate script. Blends idle, walk and run by speed with stride-matched playback, and reads the avatar's own animation pack. |
| `ProceduralLayer` | Turn lean, acceleration pitch, waist twist, head look, breathing, landing dip and foot IK on stairs and slopes. |
| `CameraRig` | Over-the-shoulder camera with a trailing pivot, aim zoom, shoulder swap, soft collision and drift back behind the character. |

## Limits

The procedural bone layer is applied only on each player's own screen. Other players see the blended animations without the extra lean and head look.

The source files are in this folder (`Desktop\RDR-Movement\src`), which is the version to edit.
