--!strict
-- Shared type definitions for ARMFORGE data definitions and runtime state.

export type Cost = { coins: number?, shards: number? }

export type ArmDef = {
	id: string,
	name: string,
	family: string,
	rarity: string, -- Common | Uncommon | Rare | Epic | Legendary
	blurb: string,
	identity: string, -- one-line gameplay identity shown in the UI
	basePower: number,
	growth: number, -- power multiplier per upgrade level
	maxLevel: number,
	upgradeBaseCost: number,
	upgradeGrowth: number,
	cooldown: number, -- seconds between strikes at base
	reach: number, -- studs
	critChance: number, -- 0..1
	critMult: number,
	pierce: number, -- 0..1, ignores this fraction of rock resistance
	coinBonus: number, -- 0..1 extra coins from rocks
	trait: string, -- id of the passive trait implemented in Logic/Damage
	traitText: string,
	attackStyle: string, -- key in Config/Animations
	cost: Cost,
	requires: { level: number?, rebirths: number?, island: string? },
	acquisition: string, -- "starter" | "purchase"
	palette: { primary: Color3, secondary: Color3, glow: Color3 },
	material: Enum.Material,
	skillsAllowed: { string }?,
}

export type RockDef = {
	id: string,
	name: string,
	family: string,
	island: string,
	tier: number,
	rare: boolean,
	maxHp: number,
	resistance: number, -- 0..0.9 fraction of damage absorbed
	coins: number,
	xp: number,
	shards: { number }?, -- {min,max}
	respawn: number,
	weight: number, -- relative spawn weight within an island
	shape: { radius: number, height: number, chunks: number, core: number, layers: number },
	colors: { shell: Color3, mid: Color3, core: Color3, glow: Color3? },
	materials: { shell: Enum.Material, mid: Enum.Material, core: Enum.Material },
	sound: string, -- key in Config/Assets.Sounds
	fx: { spark: Color3, dust: Color3 },
}

export type IslandDef = {
	id: string,
	name: string,
	tagline: string,
	order: number,
	requires: { level: number?, rebirths: number?, coins: number? },
	comingSoon: boolean?,
	center: Vector3,
	radius: number,
	rocks: { { rock: string, count: number } },
	arrival: Vector3,
	theme: { sky: Color3, ambient: Color3, fog: Color3, accent: Color3 },
}

export type SkillDef = {
	id: string,
	name: string,
	blurb: string,
	unlockLevel: number,
	maxRank: number,
	cooldown: number,
	duration: number?,
	key: number, -- hotbar slot
	rankCost: { number }, -- skill points to reach rank i
}

export type BoosterDef = {
	id: string,
	name: string,
	blurb: string,
	stat: string, -- coins | xp | power | training | crit
	bonus: number, -- additive fraction
	duration: number, -- seconds per activation
	maxDuration: number,
	color: Color3,
}

export type PlayerData = any

return {}
