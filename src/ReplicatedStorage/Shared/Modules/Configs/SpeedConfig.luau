local Config = {}

Config.Studs = 2.5
Config.TickRate = 60

Config.RunSpeed = 600
Config.AirSpeed = 450 -- air drive (7.5 u/s^2)
Config.TurnSpeed = 1.5 -- radians per second at full steer
Config.Drag = 0.0014 -- per tick
Config.Gravity = 22 -- air gravity, u/s^2 (x0.1 on the ground)
Config.FastFallSpeed = 40
Config.FastFallLerp = 0.7
Config.Boost = 0 -- drive x (1 + boost), boost capped at 5

-- Hard-coded movement constants
Config.MinSpeed = 60
Config.MinSpeedRate = 3
Config.GroundGravityMult = 0.1
Config.GroundGravityBlend = { 15, 50 }
Config.BrakeAngle = 150
Config.BrakeReleaseAngle = 90
Config.TurnRampAngle = 15
Config.LandingBlend = 0.65
Config.BadLandingThreshold = 0.7
Config.BadLandingMinSpeed = 50
Config.RewardAirTime = 1.0
Config.GoodCutoff = 0.9
Config.PerfectCutoff = 0.95
Config.LandingEnergy = { Ok = 0.03, Good = 0.055, Perfect = 0.085 }
Config.PerfectTargetSpeed = 100
Config.PerfectLerp = 0.3
Config.PerfectMaxGain = 20
Config.WallAngle = 80
Config.GroundNormalAccept = 60
Config.SnapRayUp = 2
Config.FieldEdgeMargin = 2
Config.MostlyGroundedDown = 0.5
Config.DontLandAfterBad = 0.1
Config.LaunchSpeed = 90 -- slow -> fast charge launch
Config.RestartSpeed = 100 -- respawn launch
Config.ChargeTime = 1.0
Config.SlowSwitchSpeed = 50
Config.AllowSlowMode = true
Config.AutoSlowOnLowSpeed = false

Config.SphereRadius = 0.5
Config.SphereHeight = 1.52

Config.Body = "Human"
Config.HumanCenter = 1.0

Config.Avatars = "SpeedAvatars"
Config.SolidTag = "SpeedSolid"

Config.Ball = {
	Radius = 1.0,
	Color = Color3.fromRGB(255, 120, 40),
	BandColor = Color3.fromRGB(255, 255, 255),
	Trail = false,
}

-- Edge collisions (walls / props)
Config.BonkAngle = 150
Config.BonkDamage = 15
Config.HeadOnDamage = 85
Config.PropSpeedLoss = 0.2

Config.PropPhase = 1
Config.KnockdownTime = 1.0
Config.WallBounce = 0.8

-- Look
Config.MovementLookSpring = 100
Config.PitchClamp = 80
Config.BasePitch = 20
Config.DivePitch = 20
Config.MouseDegreesPerPixel = 0.25
Config.GamepadDegreesPerSecond = 220

-- Camera (MainCamera values)
Config.Camera = {
	BaseFov = 70,
	MaxFovMult = 1.65,
	FovSpeedRange = { 50, 130 },
	OffsetFast = Vector3.new(0, 4, -15),
	OffsetSlow = Vector3.new(0, 3.5, -7),
	OffsetLerp = 2,
	WobbleSpring = 6,
	WobbleDrag = 12,
	Wobble = 0.6,
	Prediction = 0.005,
	FovSpring = 3,
	FovDrag = 4,
	SmoothVel = 5,
	AirFovMult = 0.8,
	ObstructionRadius = 0.5,
	PivotUp = 2.5,
	MaxFov = 120, -- Roblox limit

	SpeedFps = 150,
}

Config.Fx = {
	SpeedLines = true,

	ScreenLines = {
		Distance = 8,
		Fill = { 0.62, 0.55 },
		Follow = 0.35,
		From = 0.35,
		Rate = 1,
		Away = false,
	},
	SpeedBlur = true,
	BlurMax = 0.85,
	BlurSpeedRange = { 50, 130 }, -- u/s, same range as the FOV widening
	BlurFocusBand = 0.3,
	Saturation = 0.15, -- Speed colour grading: saturation +15
	Bloom = 0.35,
	DiveStreak = true,
	Dust = true,
}

-- Character visuals
Config.Visual = {
	TurnRate = 10, -- model rotation lerp, fast mode
	LeanSpring = 15,
	LeanDrag = 15,
	LeanMult = 1.0,
}

Config.Slow = {
	Speed = 130,
	Drag = 10,
	AirControl = 0.4,
	Gravity = 200,
}

-- Respawn / course
Config.KillY = -500
Config.Courses = "Courses"
Config.CourseName = "Valley"

Config.Map = {
	Scale = 0.55,          -- Speed's distances and heights x this
	Segments = 9,          -- pieces after the start piece (Speed: 5)
	Centre = Vector3.new(0, 600, 6400),
	Spacing = 500 / 255,
	Laps = 3,
	Apart = 450,

	Road = {
		HalfWidth = 100, WidthRandom = 0, Rim = 50,
		Noise = 150, NoiseRandom = 0.5, NoiseScale = 2, NoiseScaleRandom = 0.5,
	},
	Void = 500,
	Kill = 150,

	Slope = 0.8,
	Dips = {

		Spacing = { 240, 400 }, -- m crest to crest
		Depth = { 25, 50 },     -- m
		Shape = 2,

		Drop = 0.5,
		Big = { Chance = 0.3, Depth = 1.6, Spacing = 1.25 }, -- some dips this much deeper and longer
		Flat = 180,
	},
	Roll = { Wave = 180, Str = 8 },
	Hills = {
		{ Scale = 0.5, Str = 50, Exp = 1 },
		{ Scale = 1, Str = 15, Exp = 1 },
		{ Scale = 2, Str = 50, Exp = 2 },     -- Speed's own ("buff some hills")
	},
	StartPad = { Ahead = 80, Size = Vector2.new(175, 230), Rim = Vector2.new(50, 100),

		Hill = { Rise = 45, Edge = 120, Drop = 75 },   -- (~62 studs down over ~103)
	},
	EndPad = { Inner = 50, Outer = 150 }, -- m: the finish flattened in this radius
	WaypointEvery = 50,    -- m along the line

	Props = {
		Enabled = true,
		ClearStart = 140,
		ClearEnd = 120,        -- m round the finish

		Ramp = {
			Height = 0.9,
			Top = 0.9,
			Steep = 1.4,
			                   -- degrees: a ramp, not a wall)
			MinRun = 5,
		},
		Kinds = {              -- in Speed's spawn order
			{ Name = "Formations", Count = 30, Max = 6, Dist = { 0.07, 0.52 }, Size = { 0.7, 1.5 }, SizePow = 100,
				Perlin = { Wave = 50, Min = 0, Max = 0.197 }, Slope = 45, Tilt = 0.1, Rank = 10 },

			{ Name = "Trees", Count = 68, Max = 136, Dist = { 0.18, 1 }, Size = { 2, 3 }, SizePow = 6, Height = 60,
				Perlin = { Wave = 100, Min = 0, Max = 0.462 }, Slope = 45, Tilt = 0.3, Rank = 5, Shadows = 0.4, Spread = 0.45 },   -- (0.5: 121-185 trees, 0.4: 155-210)
			{ Name = "Rocks", Count = 77, Max = 160, Dist = { 0.172, 1 }, Size = { 1, 2 }, SizePow = 100,
				Perlin = { Wave = 50, Min = 0, Max = 0.435 }, Slope = 45, Tilt = 0.1, Rank = 10, RampBelow = 30 },
			{ Name = "Bushes", Count = 1000, Max = 500, Dist = { 0.094, 1 }, Size = { 1, 2 }, SizePow = 6,
				Perlin = { Wave = 100, Min = 0.248, Max = 0.352 }, Slope = 45, Tilt = 1, Rank = 1 },
			{ Name = "Debris", Count = 300, Max = 250, Dist = { 0.05, 1 }, Size = { 1, 2.5 }, SizePow = 3,
				Perlin = { Wave = 60, Min = 0, Max = 0.5 }, Slope = 45, Tilt = 1, Rank = 1, Ramp = true, Shadows = 0 },
			{ Name = "Roots", Count = 3, Max = 6, Dist = { 0.153, 1 }, Size = { 2, 3 }, SizePow = 3,
				Perlin = nil, Slope = 105, Tilt = 0.3, Rank = 5 },
		},
	},

	Pieces = {
		Enabled = true,
		Apart = 150,
		Lip = 4,
		Wall = 3,

		Gaps = { Count = { 3, 4 }, Length = { 90, 130 }, MaxShare = 0.85,

			Ramp = { Chance = 0.9, Slope = { 14, 20 }, Shape = 1.5 },
		},
		Hops = {               -- (m; x1.375 = studs at Scale 0.55)
			Count = { 2, 2 },  -- (big dips first)

			Speeds = { 85, 165 },

			Pad = 18,
			MinBefore = 40,
			Width = { 70, 95 }, -- the island across the line
			After = { 12, 20 },

			Kick = 3,
			MaxClimb = 0.08,

			KickRun = 0.45,
			Sway = 0.2,
			Thickness = { 35, 60 }, -- m of rock under the island's middle
		},
		Fall = {               -- falling into a cut
			Below = 12,
			RunUp = 40,

			Back = 220,
			Keep = 0.9,
			Speed = 150,
			Protect = 4,
			                   -- every try: a loop)
		},
	},

	Traps = {
		Enabled = true,

		Apart = 45,
		PieceClear = 15,

		Clear = 120,           -- m from the start and the finish
		CrestClear = 10,
		Hit = { SpeedLoss = 0.35 },
		Spinner = {
			Count = { 6, 9 }, Assets = { "Spinner1", "Spinner2" },
			Speed = { 100, 130 },
			Reach = 0.85,
			Radius = 4,
			Cooldown = 5,
		},
		Cage = {
			Count = { 6, 9 },
			Scale = { 0.35, 0.75 }, -- x the model (radius 133 studs)
			Lift = { -0.2, 1.9 },

			Side = 0.9,
			Tumble = { 1.5, 4.5, 1.5 },
			Cooldown = 1,

			Nodes = 132,    -- the nodes' radius (the model's: 133)
			Laser = 3,
			Phase = -18,    -- deg: the equator node's turn from +Z
			Body = 1.5,
		},
		Lava = {
			Count = { 3, 4 },

			Combos = { Cross = 0.4, Wave = 0.35 },
			GroupGap = 14,
			Height = 200,         -- studs over the road
			Sway = { 0.6, 0.95 },
			Surge = { 10, 30 },
			Speed = { 50, 85 },
			Tilt = { 4, 18 },
			Turn = { 20, 45 },    -- deg/s the tilt turns round
			Fire = 6, Rest = 1.2, -- s (grows 1, holds, shrinks 1, rests)
			Radius = 6,           -- studs: the beam and you
			Cooldown = 3,
		},

		Missile = {
			Count = { 6, 9 },
			Asset = "MissileTower",
			Scale = 1,
			Apart = 160,
			Side = 1.12,
			Sink = 6,             -- studs its foot sits under the ground
			Drop = 40,
			Spin = { 40, 70 },    -- deg/s the head turns, either way
			Interval = { 1.8, 2.6 }, -- s between salvos
			Stagger = 0.14,       -- s between a salvo's missiles
			Flight = 2,
			Arc = 90,             -- studs the arc rises over its higher end
			Window = { -220, 70 },
			RowStep = 12,         -- m between the rows it picks from
			Lanes = 5,
			Spread = 0.8,
			Radius = 28,          -- studs: a blast and you
			Blast = 0.25,         -- s a blast burns
			Cooldown = 1.2,
		},
	},
}

Config.Race = {
	Prep = 2.5,
	Hold = 1.4,              -- s the front shot holds
	Sweep = 1.9,             -- s it sweeps round behind you
	Count = 3,
	JogDistance = 47,
	RowGap = 9,
	Across = 20,             -- studs between the two columns

	AutoLaunch = true,
	Camera = {
		Ahead = 8,           -- in front of it
		Up = 1.2,
		Side = 5.5,
		Head = 3.9,
		Push = 0.12,         -- the hold creeps this share closer
		Fov = 48,
	},

	LoadTimeout = 40,
	Reveal = 1,
	DNF = 30,
	Next = 20,

	AutoNext = 10,
	Autoplay = { Tier = "Pro", UseAfter = { 1.2, 3 } },
	FinishBrake = 0.05,
	Gate = {
		HalfWidth = 1.15,
		Height = 0.75,       -- x its width: the beam's underside
		Pillar = 22,         -- studs thick
		Beam = 64,           -- studs tall
		Color = Color3.fromRGB(80, 235, 255),
		Trim = Color3.fromRGB(255, 255, 255),
		Panel = Color3.fromRGB(16, 26, 58),       -- the beam's face behind FINISH
		Curtain = Color3.fromRGB(120, 245, 255),
		Glow = 0.88,         -- the curtain's glow layer's transparency
		Text = "FINISH",
	},
}

Config.Chat = false

Config.Judge = {
	On = true,
	Traps = 0.5,
	               -- fills stay full)
	Cards = 0.7,
}

Config.Items = {
	Cards = {

		Scale = 1.7,
		Every = 260,
		Lanes = 5,            -- cards across a row ...
		Spread = 0.7,
		Lift = 7.5,           -- studs its middle floats over the ground
		AfterGap = 30,
		Clear = 60,
		Reach = 10,
		Slack = 45,
		Respawn = 3,          -- s a taken card is gone
		Draw = 900,
		Pool = 60,            -- ... at most this many at once
	},

	Pool = { Grapple = 1, Gator = 1, Drink = 1, Ink = 0.6, Shotgun = 1 },

	Show = {
		Grapple = { Display = "GRAPPLING HOOK", Icon = "Grappling Hook", Hand = "GrappleGun", HandScale = 1 },
		Gator = { Display = "GATOR", Model = "Gator", Hand = "Gator", HandScale = 0.3 },
		Drink = { Display = "ENERGY DRINK", Icon = "Energy Drink" },
		Ink = { Display = "INK", Model = "InkKit/Squid" },
		Shotgun = { Display = "SHOTGUN", Icon = "Shotgun", Hand = "Shotgun", HandScale = 1 },
	},
	BotUse = { 1.5, 4 },

	Gator = {
		ThrownScale = 0.55,   -- x the model (11 studs long) in flight
		Speed = 1.7,
		MinSpeed = 260,       -- studs/s
		Turn = 5,             -- per s it swings toward them
		Hover = 3,            -- studs over their feet it aims
		Hit = 12,             -- studs: it's got them
		Commit = 60,
		Keep = 0.15,          -- of their speed they keep
		Life = 7,             -- s it flies at most
		Forward = 300,
	},

	Drink = { Boost = 1.3, Seconds = 3, Sip = 1.1, Rate = 4 },

	Ink = {
		Image = "rbxassetid://125429173194540", Size = UDim2.fromScale(0.602, 0.98),
		Count = 6, Every = 0.1,
		Hold = 3,             -- s the screen stays inked
		Fade = 0.35, FadeEvery = 0.12,   -- s each fades, s apart
	},

	Shotgun = {
		Range = 160, Lock = 22,

		Pellets = 10, Spread = 6,   -- pellets, degrees: the cone
		Body = 6,
		Near = 0.85, Far = 0.25,
		Speed = 900,          -- studs/s a pellet flies (its look)
	},

	Grapple = {
		Display = "GRAPPLING HOOK", Icon = "Grappling Hook",
		Range = 320,          -- studs it reaches (the ground)
		RunnerRange = 260,
		Lock = 20,
		Probe = 14,
		Fly = 0.08,           -- s the hook takes to get there

		Hold = 2.5,           -- s at most (it's one use)
		LerpTo = 120, LerpAmount = 0.7, Multiplier = 1.2,
		Towards = 1, Camera = 1, Up = 0.2, Swing = 10, SpeedRate = 15,   -- per s, the pulls on your velocity
		Shake = { 10, 0.3 }, Release = { 6, 0.2 }, Fov = 15,

		Pull = 2.0,
		PullRate = 8,         -- per s your velocity swings to them
		PullSpeed = 1.3,
		Meet = 12,            -- studs apart: you've met
		Boost = 1.15,         -- x your speed when you meet
		Cap = 250,

		Overshoot = 0.35,
		Spring = 26, Damp = 7,
		Whip = 4.5, WhipRate = 30, WhipDamp = 4,
		Kick = 22,            -- the camera's FOV kick when you fire
		Keep = 0.4,
		Yank = 0.9,           -- s they're pulled back toward you
		YankRate = 4,
	},
}

Config.Bots = {
	Field = 8,

	Mix = {
		Easy = { Rookie = 4, Racer = 2, Pro = 1 },
		Normal = { Rookie = 2, Racer = 3, Pro = 2 },
		Hard = { Rookie = 0, Racer = 3, Pro = 4 },
	},
	Difficulty = "Normal",   -- (the `bots` admin command picks one)

	Friends = true,
	FriendsRead = 200,
	Tiers = {

		Rookie = { Lane = 0.6, Wander = 6, Inside = 0, Dive = 0.3, DiveLate = 0.45, GapMiss = 0.3,
			Dodge = { Cage = 0.2, Lava = 0, Spinner = 0, Missile = 0.2 }, Look = 0.6, Steer = 0.7 },
		Racer = { Lane = 0.35, Wander = 8, Inside = 0.25, Dive = 0.65, DiveLate = 0.25, GapMiss = 0.08,
			Dodge = { Cage = 1, Lava = 0.5, Spinner = 0.2, Missile = 0.5 }, Look = 0.9, Steer = 0.85 },
		Pro = { Lane = 0.15, Wander = 10, Inside = 0.55, Dive = 1, DiveLate = 0, GapMiss = 0,
			Dodge = { Cage = 1, Lava = 1, Spinner = 0.8, Missile = 0.9 }, Look = 1.2, Steer = 1 },
	},
	ClearLane = 0.18,
	Grid = { Across = 14, Back = 18, PerRow = 4 },
	Names = { "Bolt", "Zippy", "Nova", "Pixel", "Comet", "Jinx", "Sprocket", "Maple", "Rook", "Skye", "Tumble",
		"Flick", "Juno", "Kip", "Breeze", "Tango", "Wren", "Ziggy", "Mochi", "Blitz", "Scout", "Echo", "Rocket",
		"Clover", "Dart", "Fizz", "Gale", "Pebble", "Rush", "Sunny" },

	Outfits = {
		Hair = { 2956239660, 63690008, 451221329, 1103003368, 376526888, 376524487, 376548738, 376527350, 451220849,
			3814474927, 107573464938767, 3814476174, 62234425, 122614899184757, 7193442167, 14400447529, 16911622494,
			6993754725, 7193448258, 71738277767231, 9244111257, 9174355709, 9243987340, 9244095135 },
		Shirt = { 144076358, 607785314, 398633584, 144076436, 398634295, 3670737444, 382538059, 398635081, 382537702,
			382537085, 382538295, 4047884939, 4047884046, 4047886060 },
		Pants = { 144076760, 398634487, 398633812, 398635338, 382537806, 382538503, 382537569, 382537950 },
		Hat = { 607702162, 4819740796, 417457461, 617605556, 73806172412277, 1772336109, 88053067128303, 2646473721,
			607700713, 48474313, 132828583806898, 3403874988, 140417995429426, 4047554959, 3438342658, 3033908130 },
		HatChance = 0.4,
		Skin = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105),
			Color3.fromRGB(160, 105, 75), Color3.fromRGB(124, 80, 56), Color3.fromRGB(86, 58, 42) },
	},
	Colors = { Rookie = Color3.fromRGB(110, 210, 120), Racer = Color3.fromRGB(90, 160, 255), Pro = Color3.fromRGB(255, 110, 90) },
	Registry = "SpeedBots",
}

Config.Net = {
	SendRate = 30,        -- Speed_State a second
	MaxSpeed = 900,
	Slack = 1.25,
	Margin = 20,          -- studs
	Future = 0.25,
	SpawnRadius = 40,
	SpawnBelow = 1600,
	CorrectEvery = 0.5,
	History = 1,
	SnapMax = 18,
}
Config.View = {           -- other runners on your screen

	Delay = { Min = 0.05, Max = 0.6, Margin = 0.015, Rise = 0.02, Decay = 0.98 },

	Clock = { Fast = 0.1, Slow = 0.3, Gain = 2, Snap = 0.5 },
	Extrapolate = 0.1,
	Keep = 1,             -- s of reports kept per runner
	Forget = 3,           -- s without a report: its copy goes
	Folder = "SpeedRunners",
	Ghost = { Color = Color3.fromRGB(80, 200, 255), FillTransparency = 0.6 }, -- your own runner as others see it
}

Config.Hud = {
	SpeedBar = { Ticks = 10, Max = 500, Dim = 0.8 },

	SpeedColors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 156, 88), Color3.fromRGB(255, 88, 88), Color3.fromRGB(195, 16, 16) },
	MoveToStart = 5,
	FinishReach = 40,
	Map = {
		Padding = 0.12,
		Road = 0.045, Edge = 0.085,
		RoadColor = Color3.fromRGB(236, 242, 255), EdgeColor = Color3.fromRGB(22, 28, 44),
		LapColor = Color3.fromRGB(255, 214, 64), FinishColor = Color3.fromRGB(255, 255, 255),
		Gate = 0.16,
		Icon = 0.17,

		Window = { 0.26, 0.08, 0.89, 0.93 },

		Follow = { Enabled = false, Span = 2400, Anchor = Vector2.new(0.5, 0.62) },
		MineStroke = Color3.fromRGB(255, 214, 64), OtherStroke = Color3.fromRGB(255, 255, 255),
	},
	ItemRecharge = 2,   -- s per use (the `speed item use` preview)
	ItemNames = { Shotgun = "RECOIL SHOTGUN" },
	ItemKey = "LMB",

	Countdown = { Beats = 3, Beat = 1, Go = 0.85, Lead = 0.35 },
}

Config.Pace = 0.5
do
	local pace = Config.Pace
	Config.Drag /= pace
	for _, key in { "MinSpeed", "BadLandingMinSpeed", "PerfectTargetSpeed", "PerfectMaxGain", "LaunchSpeed", "RestartSpeed", "SlowSwitchSpeed" } do
		Config[key] *= pace
	end
	local function Range(r) return { r[1] * pace, r[2] * pace } end
	Config.GroundGravityBlend = Range(Config.GroundGravityBlend)
	Config.Camera.FovSpeedRange = Range(Config.Camera.FovSpeedRange)
	Config.Fx.BlurSpeedRange = Range(Config.Fx.BlurSpeedRange)
	Config.Slow.Speed *= pace
	Config.Net.MaxSpeed *= pace
	Config.Hud.SpeedBar.Max *= pace
end

Config.Loading = {
	Stages = {
		{ Key = "Track", Weight = 0.05, Status = "BUILDING NEW TRACK" },        -- the course model arrives
		{ Key = "Ground", Weight = 0.25, Status = "SHAPING THE GROUND" },       -- its heightfield (SpeedSim.FieldProgress)
		{ Key = "Paint", Weight = 0.4, Status = "PAINTING THE TERRAIN" },      -- its terrain (SpeedMapClient)
		{ Key = "Props", Weight = 0.18, Status = "PLANTING TREES & TRAPS" },   -- its props + traps
		{ Key = "Runners", Weight = 0.12, Status = "WARMING UP RUNNERS" },     -- the racers' avatars + the sounds
	},
	Waiting = "WAITING FOR RUNNERS",   -- 100% here, the others aren't yet
	Ready = "READY!",
	Tips = {
		"Hold SHIFT standing still to charge, then let it launch you.",
		"Hold SPACE in the air to DIVE: land on a downhill to keep your speed.",
		"Land SMOOTHLY along the slope for a PERFECT landing and a speed boost.",
		"Diving too early over a gap drops you in: wait till you're past the crest.",
		"Laser cages have holes: thread through them and nothing touches you.",
		"Lava beams roam across the road: watch where they're heading, not where they are.",
		"Spinning lasers sweep in a circle: time your run through the gap between the arms.",
		"Trees and rocks don't stop you, you smash right through them, but it costs speed.",
		"Fell off? You're put back just before the crest you missed: launch again!",
		"Downhill is free speed. Uphill eats it. Pick your line.",
		"The bots are your friends' avatars: beat them!",
		"Press R to start your run over.",
	},
	TipEvery = 4.5,      -- s each tip shows
}

Config.Sound = {
	Folder = "Sounds",
	Enabled = true,
	Gain = 2,   -- Roblox volume = Speed's x this
	Mix = { You = 1, Others = 0.8, Traps = 3, Ui = 0.9 },
	World = { Near = 12, Far = 375 },
	NearShare = 0.07,

	Surfaces = {
		Grass = "Grass", LeafyGrass = "Grass",
		Ground = "Dirt", Mud = "Dirt",
		Rock = "Rock", Slate = "Rock", Basalt = "Rock", Limestone = "Rock", Concrete = "Rock", Granite = "Rock", Marble = "Rock", Asphalt = "Rock",
		Pavement = "Path", Cobblestone = "Path", Brick = "Path",
		Sand = "Sand", Sandstone = "Sand",
		Snow = "Snow", Glacier = "Snow", Ice = "Snow",
		Gravel = "Gravel",
		Wood = "Wood", WoodPlanks = "Wood",
		Metal = "Metal", DiamondPlate = "Metal", CorrodedMetal = "Metal",
		Water = "Water",
	},
	DefaultSurface = "Grass",

	Ground = {
		Grass = { Step = { { "Footsteps/Grass:Step_Grass", 0.1, 3, 0.5 }, { "Footsteps/Path", 0.125, 3, 0.5 }, { "Footsteps/Grass:PlantMove", 0.75, 2, 0.5 } },
			Land = "Landing/Surface:Land_Grass" },
		Dirt = { Step = { { "Footsteps/Dirt", 0.05, 2 } }, Land = "Landing/Surface:Land_Terrain" },
		Rock = { Step = { { "Footsteps/Stone", 0.125, 1 } }, Land = "Landing/Surface:Land_Terrain" },
		Path = { Step = { { "Footsteps/Path", 0.125, 1.5, 0.3 } }, Land = "Landing/Surface:Land_Terrain" },
		Sand = { Step = { { "Footsteps/Sand", 0.125, 1.2, 0.3 }, { "Footsteps/Gravel", 0.05, 1.5 } }, Land = "Landing/Surface:Land_Terrain" },
		Snow = { Step = { { "Footsteps/Snow:Step_Snow", 0.125, 1.2, 0.3 } }, Land = "Landing/Surface:Land_Terrain" },
		Gravel = { Step = { { "Footsteps/Gravel", 0.125, 1.2, 0.3 } }, Land = "Landing/Surface:Land_Terrain" },
		Wood = { Step = { { "Footsteps/Wood", 0.125, 1, 0.2 } }, Land = "Landing/Surface:Land_Terrain" },
		Metal = { Step = { { "Footsteps/Metal", 0.1, 1, 0.2 } }, Land = "Landing/Surface:Land_Terrain" },
		Water = { Step = { { "Footsteps/Water:WaterSplash", 0.15, 1.2, 0.3 } }, Land = "Landing/Surface:Land_Terrain" },
	},

	Wind = {
		From = 40,
		Fade = 5,     -- per second toward its level
		Max = 0.45,   -- no level above this
		Grounded = { Set = "Wind/WindGrounded", Volume = 0.001, Pitch = 0.00025 },
		Air = { Set = "Wind/WindAir", Volume = 0.00067, Pitch = 0.001 },
		Fall = { Set = "Wind/WindFastFall", Volume = 0.001, Pitch = 0.002 },

		Ambience = { Set = "Extra/World/Ambience", Ground = 0.25, High = 0.05, Rate = 10 },
	},

	Steps = {
		States = { Running = "Run", SlowMovement = "Walk" },
		Run = { { "Landing/Body/Courier_Land1", 0.05, 4 }, { "Footsteps/Base:Footsteps_Alphatest", 0.05, 2 }, { "Footsteps/Base:SoftStep", 0.05, 4 } },
		Walk = { { "Footsteps/Base:Step_Cloth", 0.05, 2 }, { "Footsteps/Base:Footsteps_Alphatest", 0.1, 1 }, { "Landing/Body/Courier_Land1", 0.025, 6 } },
		WalkGround = 0.5,   -- x the ground's layer walking
		WalkFrom = 0.5,
		Within = 200,
	},

	Anim = {
		Takeoff = { { "DashSlide:DirtStep", 0.05, 1.5, 0.5 }, { "JumpFlip/Roll5", 0.05, 1.5, 0.5 }, { "Landing/Body/WallHitLayer2", 0.05, 1.5, 0.5 },
			{ "Landing/Body/Courier_Land2", 0.05, 1.5, 0.5 }, { "FastFall:Sleve", 0.05, 1.5, 0.5 } },
		TakeoffStates = { Jump1 = true, Jump2L = true, Jump2R = true, Jump3 = true, Jump4 = true, FlyStart = true },
		Flip = { { "JumpFlip:Courier_Swing|FastFall:Courier_Swing", 0.125, 0.5, 0.125 } },   -- the spins in the air
		Flips = { Jump1 = { 0.1, 0.48, 0.73 }, Jump2L = { 0.07, 0.5 }, Jump2R = { 0.07, 0.5 }, Jump3 = { 0.08 }, Jump4 = { 0, 0.67 } },   -- s in
		Land1 = { { "DashSlide:DirtStep", 0.1, 0.5 }, { "DashSlide/Roll2", 0.1, 1.5 }, { "DashSlide/Roll1", 0.1, 2 }, { "DashSlide:Courier_Land", 0.1, 1 } },
		Land2 = { { "DashSlide/Roll2", 0.25, 0.75 }, { "DashSlide/Courier_Land3", 0.25, 1 } },
		LandStates = { Land1 = "Land1", Land4 = "Land1", Land3 = "Land2", FastFallLand = "Land2" },   -- (Bad / Ok, Perfect, Good, a dive's)
		LandGround = 0.1,
		RunOut = { 0, 0.125, 0.25 },
		DiveStart = { { "FastFall:FastFall_Start", 0.125, 0.5, 0.25 }, { "FastFall/Getup", 0.05 }, { "FastFall:Sleve", 0.01 } },
		DiveEnd = { { "FastFall/Roll4", 0.05, 2 }, { "FastFall:Courier_Swing", 0.05 }, { "JumpFlip:Courier_Swing", 0.125 } },
		Hit = { { "Extra/Hit:Punch", 0.3 }, { "Extra/Hit:Punch", 0.4, 1.2, 0.3, 0.6 } },   -- the hit animation (BasicHitSFX)
		HitStates = { DamageAirR = true, DamageAirM = true, DamageAirL = true, DamageGround = true },

		Charge = { Set = "DashSlide/DashCharge", Volume = { 0.05, 0.25 }, Pitch = 3 },
	},

	You = {

		Grades = {
			Bad = { { "Landing/Body:BodyLand", 0.2, 2, 0, 0.25 }, { "Landing/Body:BodyLand", 0.35, 0.5, 0 } },   -- a low dull thud
			Ok = { { "Landing/Body:BodyLand", 0.25, 1, 0 }, { "SpeedBoost/Magic5", 0.15, 3, 0 } },            -- + a small sparkle
			Good = { { "Landing/Body:BodyLand", 0.25, 2, 0 }, { "Extra/Ui/Select", 0.25, 2, 0 } },            -- + a UI tick
			Perfect = { { "Extra/Ui/Chime", 0.2, 1, 0 }, { "Extra/Ui/Select", 0.2, 1, 0 }, { "Extra/Ui/PowerUp", 0.2, 1, 0 } },   -- a chime
		},
		Energy = { { "SpeedBoost/Magic5", 0.1 } },

		Go = { { "SpeedBoost/SpeedBoostBase", 0.25, 1 }, { "DashSlide:Skid", 0.125, 2 }, { "DashSlide:DirtStep", 0.1, 0.5 }, { "DashSlide/Roll2", 0.1, 1.5 },
			{ "DashSlide/Roll1", 0.1, 2 }, { "DashSlide:Courier_Land", 0.1, 1 } },
		Respawn = { { "Extra/World/Portal", 0.25, 1.15 } },
		Stinger = { { "Extra/Hit/Stinger", 0.1 } },          -- any hit (Speed TakeDamage's stinger)
		Trap = { { "Extra/Traps:Zap", 0.7 }, { "Extra/Hit/Stinger", 0.3 } },

		Break = {
			Tree = { { "Extra/Break:Wood", 0.25, 1, 0.25 }, { "Extra/Break:Wood", 0.25, 0.8, 0.25 }, { "Extra/Break:Smash", 0.1, 2, 0.5 } },
			Rock = { { "Extra/Break:Crack", 0.25, 1, 1 }, { "Extra/Break:Crack", 0.25, 0.5, 1 }, { "Extra/Break:Smash", 0.1, 2, 0.5 } },
			Far = 1250,
		},

		Passby = { From = 70, Ahead = 75, Side = 60, Height = 4.4, Cooldown = 0.1, Layers = { { "PassbyWhoosh", 0.25, 1, 1 } }, Pitch = 0.5, PerSpeed = 0.01 },
	},

	Others = {
		Land = "Land2",
		LandAir = 0.3,
		Hit = { { "Extra/Hit/Stinger", 0.1 }, { "Extra/Hit:Punch", 0.3 } },   -- their hit-stop
		Passby = { Layers = { { "PassbyWhoosh", 0.3, 1, 1 } }, Within = 40, Closing = 70, Cooldown = 1.2, Pitch = 0.5, PerSpeed = 0.01 },   -- flying past you
	},

	TrapNear = 0.15,
	Traps = {
		Within = 450,
		Spinner = {
			Beam = { Set = "Extra/Traps/LaserBuzz", Volume = 0.4, Far = 240 },
			Hub = { { Set = "Extra/Traps/CageHum", Volume = 0.5, Pitch = 0.5, Far = 280 }, { Set = "DashSlide/DashCharge", Volume = 0.3, Pitch = 0.5, Far = 320 } },
		},
		Cage = { { Set = "Extra/Traps/CageHum", Volume = 0.5, Pitch = 2, Far = 360 }, { Set = "DashSlide/DashCharge", Volume = 0.5, Pitch = 0.5, Far = 400 } },   -- (it's big: a little further)
		Lava = { { Set = "Extra/Traps/LavaRumble", Volume = 0.5, Far = 280 }, { Set = "Extra/Traps/LavaLoop", Volume = 0.75, Pitch = 2, Far = 180 } },   -- at the beam's end, x its size
	},

	-- THE RACE (ours: Mario Kart's), flat
	Race = {
		Beat = { { "Extra/Ui/Beep", 0.45, 1, 0 } },
		Go = { { "Extra/Ui/Beep", 0.5, 2, 0 } },      -- GO!: an octave up
		PlaceUp = { { "Extra/Ui/Swipe", 0.3, 1.15, 0 } },     -- you took a place
		PlaceDown = { { "Extra/Ui/Swipe", 0.22, 0.85, 0 } },  -- you lost one
		PlaceGap = 0.35,

		Finish = { { "Extra/World/Portal", 0.55, 1 }, { "Extra/Ui/PowerUp", 0.4, 0.8 }, { "Extra/Ui/Chime", 0.35, 1 }, { "DashSlide/DashCharge", 0.2, 1.5 } },
	},
}

return Config
