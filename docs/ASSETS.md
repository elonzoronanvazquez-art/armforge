# Assets: what is AI-generated, what is procedural, and what is borrowed

Nothing here is invented: every id was returned by a Studio tool and is checked by `tests/wiring.spec.luau` for format.

## AI-generated meshes (Studio `generate_mesh`)

Generated with the Roblox Studio MCP `generate_mesh` tool (prompts and results are in `docs/generated_assets.json`,
produced by `scripts/gen_assets.py`). Each run published a real MeshPart + texture to the creator account that ran Studio
(`publishedAssetId` in the JSON); the game loads them with `AssetService:CreateMeshPartAsync`. They are **real reusable
assets**, not previews. Inspected in Studio by placing and photographing them before use.

| Asset | Mesh id | Texture id | Size (studs) | Used for |
|---|---|---|---|---|
| CoreCrystalCyan | 108198767086062 | 70951425972568 | 4.9 x 6.0 x 4.9 | Prism Geode heart, Heartstone heart (colour stripped) |
| BoulderVein | 84191567053617 | 114644608095795 | 4.0 x 5.0 x 4.0 | generated, not used in game (kept as a registered mesh) |
| ShardA | 88741751200579 | 111917315322468 | 1.7 x 2.4 x 1.7 | generated; came back as a plain cube, NOT used |
| ShardB | 128194434014737 | 113994536637020 | 1.6 x 1.6 x 1.6 | generated; came back as a plain cone, NOT used |
| CoreQuartz | 126003500634902 | 116870406169815 | 4.0 x 6.8 x 3.9 | Quartz Spire heart |
| CoreAmethyst | 72315913314263 | 115276928882439 | 5.0 x 4.0 x 4.9 | Amethyst Cluster heart |
| CoreMagma | 124294163386112 | 116305625529658 | 4.5 x 3.7 x 3.5 | Basalt Slab / Magma Core heart |
| CoreObsidian | 120536325372690 | 101570599636057 | 5.0 x 5.0 x 5.0 | Obsidian Heart heart |
| ArmStonebreaker | 120900745139294 | 104716423497508 | 2.0 x 3.2 x 1.5 | Stonebreaker gauntlet |
| ArmAlloy | 118555248878035 | 86440920338838 | 1.7 x 3.0 x 1.6 | Alloy gauntlet |
| ArmCrystal | 116137361607302 | 105391374076938 | 1.8 x 3.2 x 1.5 | Crystal gauntlet |
| ArmMagma | 118915943920906 | 130222934109698 | 2.0 x 3.4 x 1.8 | Magma fist |
| ArmVoid | 117342570156641 | 138822422534432 | 1.1 x 3.2 x 1.9 | Void claw |
| ArmStarter | 124223543319658 | 103461283117558 | 2.1 x 2.2 x 1.2 | Starter Fists glove |
| ForgeHero | 77804505158751 | 98347797221175 | 24.9 x 22.0 x 23.0 | the Great Forge landmark |
| HaloGate | 92411368323283 | 128847417376045 | 16.7 x 15.4 x 6.0 | Skyport gate arch (all islands) |
| CrystalArch | 94377176137444 | 79479329800552 | 14.8 x 15.1 x 12.0 | Crystalfall entrance arch |
| EmberFang | 137132417558763 | 114672101356689 | 22.0 x 31.1 x 22.0 | Emberfang landmark spire |
| Pedestal | 125362622662565 | 117750215840109 | 4.0 x 3.0 x 4.5 | Armory pedestals |
| RockA | 106586035340637 | 117580761255353 | 2.9 x 1.2 x 3.0 | rock chunk (flat slab), shell/mid layers |
| RockB | 84360266223252 | 107260771398098 | 1.8 x 1.8 x 0.7 | rock chunk (boulder), shell/mid layers |
| RockC | 123307241789892 | 95251889563666 | 1.0 x 3.0 x 1.1 | rock chunk (pointed wedge), shell/mid layers |
| CrystalShard | 89820404737224 | 77065705004675 | 1.1 x 4.0 x 1.1 | crystal shards in geodes and crowns |

Design notes and limitations:

* **High-visibility items got AI meshes**: signature arm gauntlets, the Great Forge, the Skyport gate, island landmarks,
  the Armory pedestals, rock chunks and rock hearts. Everything else (terrain, training equipment, altar, crates,
  lamps, the Halo ring, UI) is **procedural from primitives** (`server/World/Build.luau`).
* Two requests came back unusable and are not used: `ShardA` (a plain cube) and `ShardB` (a plain cone), and one prompt
  ("stone gauntlet fist ... rune cracks") was refused by moderation. The first low-poly rock set was therefore
  regenerated as `RockA/B/C` with a 450-triangle budget (many chunks are on screen at once).
* The generator rejects parallel jobs ("Unable to generate Model") and must run in Edit mode with no other MCP calls in
  flight, so generation is serial.
* Rock chunk textures are dropped at runtime (`TextureID = ""`) because `MeshPart.Color` does not tint a baked texture:
  chunks use the mesh shape plus the rock's own colour and material instead. Hearts keep their baked textures.
* Gauntlets are modelled fingers-up and mirrored for the left arm (a right-hand model on the left side; thumbs are not
  mirrored, which is not noticeable at gameplay scale).
* `AssetService:CreateMeshPartAsync` is called once per asset and the result cloned; collision fidelity is set through its
  options table (the property itself is not scriptable). If a mesh fails to load the builders fall back to primitives
  (`ArmDesigns` pieces marked `fallback`, `RockBuilder` Part/Wedge chunks, `Build.mesh` returning nil).
* **Licensing/ownership:** the meshes belong to the Roblox account that generated them. They work in experiences owned by
  that account; if the experience is moved to a group, re-upload or transfer them. Verify Roblox's current terms for
  AI-generated content before monetising.

## Sounds

All 36 sound slots in `Config/Assets.Sounds` use free **ProSoundEffects** library assets found with Studio's
`search_asset` (Creator Store, free) plus Roblox's own UI click (`15675059323`). All were verified in Studio to load
(`IsLoaded` and a non-zero `TimeLength`). Long assets are clipped with a start/length window. Several slots reuse a source
sound at a different pitch (e.g. coins, level-up) because no suitable coin or fanfare asset was found; **a bespoke audio
pass is a next step**. There is no music.

## Not generated

`generate_material` / `generate_texture` were not used: runtime-created MaterialVariants would not persist through the
Rojo build, and the stock terrain/part materials with tinted colours were sufficient for this sprint.
