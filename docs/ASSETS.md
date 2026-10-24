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

## Creatures (rock encounters)

Twelve of the thirteen creatures are built from **segmented AI rigs**: Studio's `generate_mesh` with `segmentation = "explicit"` returns
the torso, head, arms and legs (quadrupeds: body, head, tail, four legs) as separate MeshParts with their own textures
(`scripts/gen_rigs.py`; prompts, part lists and raw results in `docs/generated_assets.json`). `scripts/export_rigs.py` writes every id into
`src/shared/Config/CreatureRigs.luau`, and `server/World/CreatureBuilder` scales the parts to the creature's height, turns them to
face -Z and joins them with Motor6Ds named `J_Body`, `J_Head`, `J_ArmL/R`, `J_LegL/R` (or `J_LegFL/FR/BL/BR`, `J_Tail`). The client animation
moves those joints, so the limbs really swing (`tests/wiring.spec` checks every id against the generation record).

| Creature | Tier / island | Rig (parts) | Inspected in Studio | Notes / limits |
|---|---|---|---|---|
| Cairn Crawler | normal, Forgeheart | single AI mesh `CreatureCrawler` (stone turtle) + procedural legs | yes | the mesh faces +X (yaw 90); cuter than the prompt |
| Prism Wisp | normal (rare), Forgeheart | procedural shard template + existing AI crystal `CoreCrystalCyan` | yes | crystal mesh reused from the rocks |
| Shardling | normal, Crystalfall | procedural shard template + existing `CoreQuartz` | not individually | |
| Slag Brute | normal, Forgeheart | `RigBrute` (6) | rig laid out in Edit, fought in Play | rust-orange iron golem |
| Quarry Colossus | elite, Forgeheart | `RigColossus` (6) | yes | stone golem with shoulder spikes, glowing chest gem |
| Grom, the Anvil-King | guardian, Forgeheart | `RigAnvilKing` (6) | yes | armored king with an anvil crown |
| Amethyst Warden | normal, Crystalfall | `RigWarden` (6) | laid out in Edit | violet crystal sentinel; small (it is a medium-rock creature) |
| Choir Behemoth | elite, Crystalfall | `RigChoir` (6) | laid out in Edit | came back as a winged ice figure, thin (1.7 deep): a distinct silhouette but not hulking |
| Lyrae, the Frozen Chorus | guardian, Crystalfall | `RigLyrae` (6) | laid out in Edit | tall ice queen with crystal pipes on the shoulders |
| Ash Hound | normal, Emberfang | `RigAshHound` (7) | yes (parts measured: head forward, tail behind) | four-legged basalt hound, faces -Z as generated |
| Magma Golem | normal, Emberfang | `RigMagmaGolem` (6) | laid out in Edit | grey crust golem, less fiery than prompted (its first generation failed with an HTTP 504 and was retried) |
| Obsidian Executioner | elite, Emberfang | `RigObsidian` (6) | laid out in Edit | |
| Cinderjaw Sovereign | guardian, Emberfang | `RigCinderjaw` (6) | laid out in Edit | blue-stone torso with violet cracks and ember limbs; it does not look like the "black basalt and lava" prompt |

The earlier one-piece meshes (`CreatureBrute` 111108270303063, `CreatureColossus` 83897845854526, `CreatureAnvilKing` 83130551069179 in `Config/Assets`)
stay registered as the fallback: if any rig part fails to load the builder discards the rig and uses the one-piece mesh, and if that fails too, the
procedural body template. Generated palettes do not always match the prompts or the creature's `visual` colours (those only tint the
procedural fallback, the telegraphs and the effects).

Orientation is per generation: all biped rigs face +Z as generated (`meshYaw = 180`), the hound faces -Z (`meshYaw = 0`), the turtle +X (`meshYaw = 90`).
This was verified in Studio for the Colossus, Grom and the hound (part positions); the remaining biped rigs follow the same convention but
the final posed screenshots could not be captured (the Studio screenshot tool stopped responding late in the session), so their facing
and poses were checked by measuring joint positions, not by eye.

**Animation is procedural, not authored**: the client sets `Motor6D.Transform` from the replicated creature state in
`client/Controllers/CreatureController`. No animation asset was created or uploaded. Measured on Grom (joint positions, 16-stud rig): idle arms
at hip height (8.3), windup raises both fists to 16.1 and rears the body back, the strike swings them forward and down (z -2.6) with the body
leaning in, stagger leans back, defeat slumps and sinks. Textured meshes cannot be tinted through Color, so armor-broken and exposed-core
states are shown with a fill highlight (gold pulse for the core, ember for broken armor).

Everything has a fallback and the generated meshes belong to the account that ran Studio (same licensing note as above).

## Biome sprint: nothing AI-generated

The jungle (Mossveil), desert (Dustwake), mountain, volcano, steampunk foundry and fishing dock are built entirely from primitives (`World/Flora`, the island
modules): trees, palms, vines, ruins, the colossus head, pyramid and ribcage are parts, not meshes. The eight new creatures use the procedural
crawler / brute / titan bodies tinted from `visual`. No `generate_mesh` or audio search was run; the two new ambience beds reuse existing
loop ids at their own volumes (placeholders).

## Sounds

All 36 sound slots in `Config/Assets.Sounds` use free **ProSoundEffects** library assets found with Studio's
`search_asset` (Creator Store, free) plus Roblox's own UI click (`15675059323`). All were verified in Studio to load
(`IsLoaded` and a non-zero `TimeLength`). Long assets are clipped with a start/length window. Several slots reuse a source
sound at a different pitch (e.g. coins, level-up) because no suitable coin or fanfare asset was found; **a bespoke audio
pass is a next step**. There is no music.

## Not generated

`generate_material` / `generate_texture` were not used: runtime-created MaterialVariants would not persist through the
Rojo build, and the stock terrain/part materials with tinted colours were sufficient for this sprint.
