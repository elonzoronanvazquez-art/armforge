--!strict
-- Signature moves: every arm has one special attack of its own, used with Q (or the SIGNATURE slot on touch) while that arm is
-- worn. They need no skill points; each has its own cooldown, tracked per arm so swapping arms never skips it.
--
-- A signature is a short script of strikes against the target (times in seconds from the start of its animation, which is
-- built so the fists land on those beats) and an optional burst of area damage. Damage is `power x mult`, resolved by
-- Logic/Combat with the arm's own crit and pierce, then mitigated by each target's resistance like any other hit.

local Signatures = {}

export type Strike = {
	at: number, -- seconds after the move starts
	mult: number, -- multiplier on the arm's power
	crit: boolean?, -- guaranteed crit
}

export type Burst = {
	at: number,
	radius: number,
	maxTargets: number,
	mult: number,
	center: string, -- "self" (the wearer) | "target" (the struck target, which the burst skips)
	ignite: boolean?,
}

export type SignatureDef = {
	armId: string,
	name: string,
	blurb: string,
	move: string, -- Config/Animations move
	cooldown: number,
	needsTarget: boolean,
	strikes: { Strike },
	burst: Burst?,
	pierce: number?, -- extra armor piercing on every hit of this move
	ignite: boolean?, -- the strikes set rocks alight (and add Magma's burn to creatures)
	style: string, -- visual identity, read by the client effects
}

Signatures.Defs = {
	Starter = {
		armId = "Starter",
		name = "Knuckle Barrage",
		blurb = "Four lightning jabs, then a haymaker that hits twice as hard.",
		move = "BarrageFlurry",
		cooldown = 11,
		needsTarget = true,
		strikes = {
			{ at = 0.25, mult = 0.8 },
			{ at = 0.4, mult = 0.8 },
			{ at = 0.55, mult = 0.8 },
			{ at = 0.7, mult = 0.8 },
			{ at = 0.98, mult = 2.2 },
		},
		style = "barrage",
	},
	Stonebreaker = {
		armId = "Stonebreaker",
		name = "Quake Stomp",
		blurb = "Stamp the ground: a quake batters every rock and creature around you.",
		move = "QuakeStomp",
		cooldown = 12,
		needsTarget = false,
		strikes = {},
		burst = { at = 0.62, radius = 16, maxTargets = 5, mult = 1.7, center = "self" },
		style = "quake",
	},
	Alloy = {
		armId = "Alloy",
		name = "Piston Storm",
		blurb = "Eight piston jabs in under a second, and your Overclock leaps to full stacks.",
		move = "PistonStorm",
		cooldown = 10,
		needsTarget = true,
		strikes = {
			{ at = 0.3, mult = 0.55 },
			{ at = 0.4, mult = 0.55 },
			{ at = 0.5, mult = 0.55 },
			{ at = 0.6, mult = 0.55 },
			{ at = 0.7, mult = 0.55 },
			{ at = 0.8, mult = 0.55 },
			{ at = 0.9, mult = 0.55 },
			{ at = 1.0, mult = 0.55 },
		},
		style = "storm",
	},
	Crystal = {
		armId = "Crystal",
		name = "Prism Lance",
		blurb = "One perfect thrust, always a crit, that refracts into the rocks and creatures beside the target.",
		move = "PrismLance",
		cooldown = 12,
		needsTarget = true,
		strikes = { { at = 0.7, mult = 1.9, crit = true } },
		burst = { at = 0.78, radius = 14, maxTargets = 3, mult = 0.9, center = "target" },
		style = "lance",
	},
	Magma = {
		armId = "Magma",
		name = "Eruption",
		blurb = "Leap and slam. The target ignites and the ground erupts, setting everything nearby alight.",
		move = "EruptionSlam",
		cooldown = 13,
		needsTarget = true,
		strikes = { { at = 0.66, mult = 2.4 } },
		burst = { at = 0.7, radius = 15, maxTargets = 4, mult = 1.0, center = "target", ignite = true },
		ignite = true,
		style = "eruption",
	},
	Void = {
		armId = "Void",
		name = "Rift Tear",
		blurb = "Rip a seam in space. It cuts through armor and tears at the targets around it.",
		move = "RiftTear",
		cooldown = 14,
		needsTarget = true,
		strikes = { { at = 0.7, mult = 3.2 } },
		burst = { at = 0.74, radius = 12, maxTargets = 3, mult = 1.2, center = "target" },
		pierce = 0.6,
		style = "rift",
	},
} :: { [string]: SignatureDef }

return Signatures
