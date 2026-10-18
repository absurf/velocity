# VELOCITY

A fast, momentum-based multiplayer racer for Roblox, built at **SwampHacks XII** (University of Florida, October 16–18, 2026).

Every race happens on a new course generated from a seed: a downhill grass road with dips, hills, gaps and set pieces, plus trees, rocks and traps. Runners build speed off slopes and clean landings, dive to fall faster, grab items (Recoil Shotgun, Grapple, Energy Drink, Banana and others) and race up to six at a time. AI racers fill empty spots.

## How it works

All game logic is Luau, written in Roblox Studio.

| Area | Where | What it does |
|---|---|---|
| Movement sim | `Shared/Modules/Speed/SpeedSim` | Fixed 60 Hz simulation of each runner (position + velocity, ground rays, slopes, landings, dive, grapple). It doesn't use a Humanoid or Roblox physics. |
| Course generator | `Shared/Modules/Speed/Courses/Generated` | Seed → road line, heightfield ground, dips and hills, props, traps, item cards, finish gate |
| Multiplayer | `SpeedServiceClient` / `SpeedServiceServer` / `SpeedRunnersClient` | Each client reports its runner ~30×/s in packed bytes (`RunnerPack`). The server checks every report against speed limits and relays it, and other screens draw a smoothed copy (`RunnerPath`). |
| AI racers | `SpeedBotServer`, `Shared/Modules/Speed/BotBrain` | Bots run the same sim on the server and follow the course line in their own lanes. They dodge traps and use items. |
| Race | `SpeedRaceServer` / `SpeedRaceClient`, `CourseTrack` | Countdown, places, finish, results |
| Items + traps | `SpeedItemServer` / `SpeedItemClient`, `Traps`, `SpeedMissileClient` | Item cards and their effects. Traps move on the server clock, so every screen agrees on where they are. |
| Feel | `SpeedCameraClient`, `SpeedEffectsClient`, `SpeedSoundClient`, `SpeedVFXClient` | Speed-driven FOV, speed lines, layered sounds, landing and finish effects |
| UI | `ReplicatedStorage/UI` | HUD holders (speed, place, minimap, item, results), loading screen, player markers, reticle |
| Admin | `ServerScriptService/Initiator/GameCommands` | Cmdr commands for testing and the expo (`map`, `bots`, `race`, `autoplay`, `judge`, …) |

### Layout

`src/` mirrors the place's Explorer tree, using Rojo naming:

- `*.server.luau` is a Script.
- `*.client.luau` is a LocalScript.
- `init.luau` is a module that has child modules.

`ServerScriptService/Initiator` loads every server service module. `StarterPlayerScripts/Host` loads every client service and UI module.

Models, terrain, sounds, images and UI layouts live in the Roblox place and aren't part of this repo. The same goes for edit-time builder tools and third-party libraries (listed below).

## Credits

### AI tools (required disclosure)
- **Claude Code** (Anthropic) helped write and debug much of the Luau code.
- **OpenAI Codex / ChatGPT * made the planning for the game design

### Libraries used (not included here; all by their own authors)
- [Cmdr](https://github.com/evaera/Cmdr) by evaera: admin command console
- [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) by loleris: player data
- [ByteNet](https://github.com/ffrostfall/ByteNet) by ffrostfall: the networking layer under our network handler
- [RbxUtil](https://github.com/Sleitnick/RbxUtil) by Sleitnick: Signal, Trove, Input
- ForgeVFX: particle and VFX playback
- Spring by bhristt: spring physics module
- AlyaNum: number formatting

### Code from before the hackathon
- Our in-house utility modules (`AbsurfUtility`, `AbsurfTaskScheduler`, `AbsurfNetworkHandler`, `AbsurfTagHandler`, `AnimationHandler`, `AudioHandler`) were written before SwampHacks.
- Parts of our earlier game Stardust were reused as a base. The SwampHacks organizers approved this reuse.
