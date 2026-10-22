--!strict
-- Asset registry. Every id here is a REAL asset:
--   * Meshes: produced by Roblox Studio's generate_mesh AI tool; ids recorded in docs/generated_assets.json.
--   * Sounds: free ProSoundEffects library entries found with Studio's search_asset (Creator Store), plus Roblox's
--     own UI click. No id is invented. If an asset fails to load, the client falls back to a silent/primitive stand-in.
-- Anything the game depends on has a procedural fallback (see Runtime/RockBuilder and Runtime/ArmBuilder).

local Assets = {}

export type MeshAsset = { mesh: string, texture: string?, size: Vector3 }

-- AI-generated meshes (filled in from docs/generated_assets.json by hand after each generation run).
Assets.Meshes = {
	CoreCrystalCyan = { mesh = "rbxassetid://108198767086062", texture = "rbxassetid://70951425972568", size = Vector3.new(4.88, 6, 4.91) },
	BoulderVein = { mesh = "rbxassetid://84191567053617", texture = "rbxassetid://114644608095795", size = Vector3.new(3.99, 5, 3.98) },
	CoreQuartz = { mesh = "rbxassetid://126003500634902", texture = "rbxassetid://116870406169815", size = Vector3.new(4, 6.83, 3.93) },
	CoreAmethyst = { mesh = "rbxassetid://72315913314263", texture = "rbxassetid://115276928882439", size = Vector3.new(5, 4, 4.89) },
	CoreMagma = { mesh = "rbxassetid://124294163386112", texture = "rbxassetid://116305625529658", size = Vector3.new(4.5, 3.69, 3.48) },
	CoreObsidian = { mesh = "rbxassetid://120536325372690", texture = "rbxassetid://101570599636057", size = Vector3.new(5, 5.03, 4.99) },
	ArmStonebreaker = { mesh = "rbxassetid://120900745139294", texture = "rbxassetid://104716423497508", size = Vector3.new(1.99, 3.2, 1.52) },
	ArmAlloy = { mesh = "rbxassetid://118555248878035", texture = "rbxassetid://86440920338838", size = Vector3.new(1.74, 3, 1.57) },
	ArmCrystal = { mesh = "rbxassetid://116137361607302", texture = "rbxassetid://105391374076938", size = Vector3.new(1.83, 3.2, 1.5) },
	ArmMagma = { mesh = "rbxassetid://118915943920906", texture = "rbxassetid://130222934109698", size = Vector3.new(2.02, 3.4, 1.84) },
	ArmVoid = { mesh = "rbxassetid://117342570156641", texture = "rbxassetid://138822422534432", size = Vector3.new(1.12, 3.2, 1.88) },
	ArmStarter = { mesh = "rbxassetid://124223543319658", texture = "rbxassetid://103461283117558", size = Vector3.new(2.11, 2.2, 1.24) },
	ForgeHero = { mesh = "rbxassetid://77804505158751", texture = "rbxassetid://98347797221175", size = Vector3.new(24.88, 22, 23.01) },
	HaloGate = { mesh = "rbxassetid://92411368323283", texture = "rbxassetid://128847417376045", size = Vector3.new(16.7, 15.44, 6) },
	CrystalArch = { mesh = "rbxassetid://94377176137444", texture = "rbxassetid://79479329800552", size = Vector3.new(14.79, 15.13, 12) },
	EmberFang = { mesh = "rbxassetid://137132417558763", texture = "rbxassetid://114672101356689", size = Vector3.new(21.99, 31.09, 22) },
	Pedestal = { mesh = "rbxassetid://125362622662565", texture = "rbxassetid://117750215840109", size = Vector3.new(3.98, 3, 4.52) },
	RockA = { mesh = "rbxassetid://106586035340637", texture = "rbxassetid://117580761255353", size = Vector3.new(2.94, 1.16, 3.00) },
	RockB = { mesh = "rbxassetid://84360266223252", texture = "rbxassetid://107260771398098", size = Vector3.new(1.85, 1.80, 0.68) },
	RockC = { mesh = "rbxassetid://123307241789892", texture = "rbxassetid://95251889563666", size = Vector3.new(1.04, 3.00, 1.06) },
	CrystalShard = { mesh = "rbxassetid://89820404737224", texture = "rbxassetid://77065705004675", size = Vector3.new(1.07, 4.00, 1.07) },
} :: { [string]: MeshAsset }

export type Sound = { id: string, volume: number, pitch: { number }, start: number?, length: number? }

local function s(id: number, volume: number, lo: number, hi: number, start: number?, length: number?): Sound
	return { id = "rbxassetid://" .. id, volume = volume, pitch = { lo, hi }, start = start, length = length }
end

Assets.Sounds = {
	Swing = { s(9120972321, 0.35, 0.9, 1.15), s(9120972444, 0.35, 0.9, 1.15), s(9120972323, 0.35, 0.9, 1.15) },
	HitStone = { s(9125869504, 0.55, 0.9, 1.1, 0, 0.9), s(9125869495, 0.55, 0.9, 1.1, 0, 0.9), s(9125869138, 0.55, 0.9, 1.1, 0, 0.9) },
	HitMetal = { s(9119072660, 0.6, 0.85, 1.1), s(9119072674, 0.6, 0.85, 1.1), s(9116524438, 0.5, 0.9, 1.1, 0, 0.9) },
	HitCrystal = { s(9116418035, 0.4, 1.3, 1.6, 0, 1.0), s(9116420454, 0.35, 1.4, 1.8, 0, 1.0), s(9125647212, 0.35, 1.3, 1.7, 0, 1.0) },
	HitMagma = { s(9118612665, 0.55, 0.7, 0.9, 0, 1.0), s(9114277757, 0.35, 0.8, 1.0, 0, 0.8) },
	HitObsidian = { s(9118617342, 0.6, 0.6, 0.8, 0, 1.0), s(9114277757, 0.4, 0.6, 0.8, 0, 0.8) },
	BreakStone = { s(9125869797, 0.8, 0.85, 1.0, 0, 1.6), s(9125869505, 0.8, 0.85, 1.0, 0, 1.6), s(9118612665, 0.8, 0.9, 1.05, 0, 1.6) },
	BreakMetal = { s(9116541505, 0.7, 0.9, 1.1, 0, 1.6), s(9116329922, 0.8, 0.9, 1.0, 0, 1.6) },
	BreakCrystal = { s(9114858583, 0.7, 1.2, 1.5, 0, 1.4), s(9125602386, 0.35, 1.0, 1.1, 0, 1.8) },
	BreakMagma = { s(9116329922, 0.9, 0.7, 0.85, 0, 1.8), s(9114429740, 0.5, 1.0, 1.0, 0, 1.8) },
	BreakObsidian = { s(9116329922, 0.9, 0.6, 0.75, 0, 1.8), s(9114858583, 0.6, 0.8, 1.0, 0, 1.4) },
	Crit = { s(9114277757, 0.45, 1.5, 1.8, 0, 0.6) },
	Smash = { s(9116477061, 0.9, 0.9, 1.0, 0, 1.6) },
	Coin = { s(9119072660, 0.25, 2.2, 2.6, 0, 0.5) },
	LevelUp = { s(9116418035, 0.6, 1.0, 1.0, 0, 2.4), s(9125602386, 0.4, 1.0, 1.0, 0, 3.0) },
	Click = { s(15675059323, 0.5, 1.0, 1.0) },
	Equip = { s(9116524438, 0.5, 1.2, 1.3, 0, 0.7) },
	Upgrade = { s(9116418035, 0.5, 1.6, 1.8, 0, 1.0) },
	Rebirth = { s(9125602386, 0.8, 0.9, 0.9, 0, 4.0), s(9116329922, 0.7, 0.7, 0.8, 0, 2.5) },
	Spawn = { s(9116420454, 0.25, 1.8, 2.0, 0, 0.7) },
} :: { [string]: { Sound } }

return Assets
