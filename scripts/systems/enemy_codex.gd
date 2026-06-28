class_name EnemyCodex
extends Object
## Single source of truth for the enemy bestiary. Each entry carries everything
## the Encyclopedia needs to stage and describe a hostile: the in-game scene to
## spawn as a live, animated model, display name + dossier, and the tactical
## breakdown (strengths / weaknesses / which weapons counter it). The same scene
## files the player fights are shown, so the codex never drifts from the game.
##
## `scale` / `y` mirror the framing values the old level briefing used so each
## chassis sits centred and uncropped in the viewer's lens.

## Ordered roster — roughly the order the campaign introduces them (grunts →
## specials → bosses). The Encyclopedia shows only the ones the player has met.
const ORDER: Array = [
	"drone", "android", "spider", "mech", "skitter", "vacuum",
	"hunter", "reaper", "strider", "sniper", "seeker", "brute",
	"gunner", "raptor", "mender", "sentinel", "mauler", "ravager", "warmech", "dog", "server", "alien",
	"magma", "fishbot", "warbot", "enforcer", "ripper", "optic", "roller", "shark", "gunslinger",
	"whirlwind", "breaker",
	"terminator", "overseer", "colossus", "smasher", "titan", "archon",
]

const ENTRIES := {
	"drone": {
		"scene": "res://scenes/enemies/drone.tscn", "name": "RECON DRONE", "scale": 1.0, "y": 1.6,
		"desc": "A skittish flying eye that strafes and dives, peppering you with light bolts.",
		"strengths": ["Fast and erratic — hard to track in the air", "Attacks from angles ground units can't"],
		"weaknesses": ["Paper-thin armour — one solid hit drops it", "Predictable dive telegraphs its approach"],
		"weapons": ["AR-7 Pulse Rifle", "MK-VII Longshot", "M9 Sidearm"],
	},
	"magma": {
		"scene": "res://scenes/enemies/magma.tscn", "name": "MAGMA WRAITH", "scale": 1.0, "y": 1.6,
		"desc": "A molten foundry drone crowned in glowing horns. Hovers over the lava and lobs scorching bolts while you balance on the catwalks.",
		"strengths": ["Up-armoured — soaks more than a recon drone", "Fights over the lava where a miss means a fall"],
		"weaknesses": ["Slower and more deliberate than a recon drone", "Big glowing silhouette — easy to track"],
		"weapons": ["AR-7 Pulse Rifle", "PL-1 Plasma Launcher", "MK-VII Longshot"],
	},
	"fishbot": {
		"scene": "res://scenes/enemies/fishbot.tscn", "name": "ANGLER UNIT", "scale": 1.0, "y": 1.6, "light": 0.5,
		"desc": "A robotic deep-sea fish that prowls the flooded basins — finned, darting and trailing bubbles, spitting pressurised water bolts.",
		"strengths": ["Very fast and darting — hard to track", "Harasses you across the gantries from any angle"],
		"weaknesses": ["Fragile — a solid hit drops it", "Predictable swim-in to harpoon range"],
		"weapons": ["SG-12 Breacher", "NV-X Nova Scatter", "VK-7 Tesla Projector"],
	},
	"warbot": {
		"scene": "res://scenes/enemies/warbot.tscn", "name": "WAR-BOT B0", "scale": 0.8, "y": 0.0,
		"desc": "A stout bipedal war-bot with twin arm-cannons. Its face-screen beams a cheery GREEN smile as it patrols — then snaps to a RED scowl the instant it locks on, and opens up with burst fire.",
		"strengths": ["Sturdier than a standard android — soaks more fire", "Flanks and dodges between bursts", "Twin cannons rake you at mid range"],
		"weaknesses": ["The green-to-red face flip telegraphs the moment it engages", "Headshots still drop it fast", "Slower to wheel around than lighter units"],
		"weapons": ["AR-7 Pulse Rifle", "GEM-2 Twin Rail", "MK-VII Longshot"],
	},
	"enforcer": {
		"scene": "res://scenes/enemies/enforcer.tscn", "name": "ENFORCER", "scale": 1.0, "y": 0.0, "light": 1.6,
		"desc": "The AI's armoured riot trooper — a sleek police-frame android bracing a heavy scifi rifle. Holds its ground at range, fires measured bursts, and shrugs off chip damage.",
		"strengths": ["Tougher and better armoured than an android", "Accurate burst fire at long range", "Holds position behind cover"],
		"weaknesses": ["Slow to reposition — flank it", "Headshots still drop it fast"],
		"weapons": ["AR-7 Pulse Rifle", "MK-VII Longshot", "GEM-2 Twin Rail"],
	},
	"ripper": {
		"scene": "res://scenes/enemies/ripper.tscn", "name": "RIPPER", "scale": 1.0, "y": 0.0,
		"desc": "A walking minigun platform. It plants at mid range and saws off long, rapid bolt-bursts to pin you down. Lightly armoured for its firepower — flank it while it's committed to a burst.",
		"strengths": ["Brutal sustained suppressing fire", "Wears you down through cover chip"],
		"weaknesses": ["Locked in place mid-burst — flank it", "Thin armour for a heavy"],
		"weapons": ["GRK-X Devastator", "ARC-9 Gauss Lance", "MK-VII Longshot"],
	},
	"optic": {
		"scene": "res://scenes/enemies/optic.tscn", "name": "OPTICON", "scale": 1.0, "y": 0.0,
		"desc": "A repurposed maintenance unit — a boxy body slung under a single glaring red optic, scuttling on spindly tool-legs. Built to weld and repair; now it lances you with its cutting beam.",
		"strengths": ["Its cutting beam stings", "Small, awkward target on skittering legs"],
		"weaknesses": ["Slow and fragile — focus it down", "No armour to speak of"],
		"weapons": ["AR-7 Pulse Rifle", "SG-12 Breacher", "VK-7 Tesla Projector"],
	},
	"roller": {
		"scene": "res://scenes/enemies/roller.tscn", "name": "ROLLER", "scale": 1.0, "y": 0.0, "light": 1.6,
		"desc": "A monowheel brawler — a heavy drum balanced on one fat wheel, whipping spring-arms. It rolls in fast and rams, knocking you back. Tougher than a hound but slower to turn.",
		"strengths": ["Closes distance in a fast roll", "Tanky — soaks a lot before it drops", "Rams hard and knocks you off balance"],
		"weaknesses": ["No ranged attack — kite it", "Wide turning circle — circle-strafe it"],
		"weapons": ["SG-12 Breacher", "GRK-X Devastator", "NV-X Nova Scatter"],
	},
	"shark": {
		"scene": "res://scenes/enemies/shark.tscn", "name": "RAZORFIN", "scale": 1.0, "y": 1.3, "light": 0.5,
		"desc": "A robotic shark that prowls BELOW the flooded basin, showing only a wake as it stalks the gantries. When it strikes it BREACHES — rocketing up out of the water in an arc to snap at you, then crashing back under. Hard to hit while submerged.",
		"strengths": ["Lurks underwater where shots can't reach", "Breaches in a fast arc that's tough to dodge on a narrow gantry", "Snaps for heavy damage at the top of a leap"],
		"weaknesses": ["Exposed and committed at the apex of a breach — punish it there", "Predictable arc once it launches"],
		"weapons": ["SG-12 Breacher", "NV-X Nova Scatter", "AR-7 Pulse Rifle"],
	},
	"gunslinger": {
		"scene": "res://scenes/enemies/gunslinger.tscn", "name": "GUNSLINGER", "scale": 1.0, "y": 0.0, "light": 1.6,
		"desc": "A brass steampunk automaton with a heavy revolver arm. It fires single, hard-hitting slugs on a slow cadence and dances aside between shots. Punishing if you stand still — bait it into a wasted shot, then close in.",
		"strengths": ["Heavy single slugs hurt", "Strafes constantly between shots", "Long engagement range"],
		"weaknesses": ["Slow cadence — exploit the gap after a shot", "Modest health"],
		"weapons": ["MK-VII Longshot", "AR-7 Pulse Rifle", "ARC-9 Gauss Lance"],
	},
	"whirlwind": {
		"scene": "res://scenes/enemies/whirlwind.tscn", "name": "WHIRLWIND", "scale": 1.0, "y": 1.3,
		"desc": "A hovering buzzsaw drone: a red core slung between two long whirling blade-arms. It floats over the field, then dives in to rake you with its spinning arms before pulling back up out of reach.",
		"strengths": ["Airborne — harder to pin than ground units", "Dives in fast for melee rakes", "Erratic flight"],
		"weaknesses": ["No ranged attack — keep it at bay", "Falls to sustained fire"],
		"weapons": ["AR-7 Pulse Rifle", "SG-12 Breacher", "MK-VII Longshot"],
	},
	"breaker": {
		"scene": "res://scenes/enemies/breaker.tscn", "name": "BREAKER", "scale": 1.0, "y": 1.3, "yaw": 90.0,
		"desc": "A hovering bronze sphere-bot built around a glowing core, dragging a massive piston hammer. It floats in, bobbing, then dives to slam you before drifting back up. Pure melee — shoot it down before it closes.",
		"strengths": ["Floats above the fight and dives to smash", "Hammer slam hits hard", "Tougher than a recon drone"],
		"weaknesses": ["No ranged attack — punish it at range", "Slow, glowing, easy to track"],
		"weapons": ["MK-VII Longshot", "GRK-X Devastator", "AR-7 Pulse Rifle"],
	},
	"android": {
		"scene": "res://scenes/enemies/android.tscn", "name": "INFANTRY ANDROID", "scale": 1.0, "y": 0.0,
		"desc": "The AI's rank-and-file rifleman. Flanks, takes cover, and swarms in packs.",
		"strengths": ["Comes in numbers and spreads out", "Decent range and steady fire"],
		"weaknesses": ["Lightly armoured", "Headshots end it instantly"],
		"weapons": ["AR-7 Pulse Rifle", "SG-12 Breacher", "NV-X Nova Scatter"],
	},
	"spider": {
		"scene": "res://scenes/enemies/spider.tscn", "name": "STALKER", "scale": 1.0, "y": 0.0,
		"desc": "A low, fast quadruped that closes the gap and lunges in to bite.",
		"strengths": ["Very fast — eats distance quickly", "Small, hugs the ground, hard to hit far off"],
		"weaknesses": ["No ranged attack — useless if kept at distance", "Fragile body"],
		"weapons": ["SG-12 Breacher", "NV-X Nova Scatter", "VK-7 Tesla Projector"],
	},
	"mech": {
		"scene": "res://scenes/enemies/mech.tscn", "name": "HEAVY MECH", "scale": 1.0, "y": 0.0,
		"desc": "An armoured bruiser that charges in and ground-slams at melee range.",
		"strengths": ["Heavily armoured — soaks small-arms fire", "Hits like a truck up close"],
		"weaknesses": ["Slow to turn — strafe around it", "Big target for heavy weapons"],
		"weapons": ["GRK-X Devastator", "ARC-9 Gauss Lance", "GEM-2 Twin Rail"],
	},
	"skitter": {
		"scene": "res://scenes/enemies/skitter.tscn", "name": "SKITTER", "scale": 2.2, "y": 0.0,
		"desc": "Tiny, fast, fragile — and never alone. They pour in by the dozen and surround you.",
		"strengths": ["Overwhelm by sheer numbers", "Fast and tiny — hard to pick off individually"],
		"weaknesses": ["Dies to a stiff breeze", "Bunches up — perfect for splash and chain hits"],
		"weapons": ["NV-X Nova Scatter", "VK-7 Tesla Projector", "SG-12 Breacher"],
	},
	"vacuum": {
		"scene": "res://scenes/enemies/vacuum.tscn", "name": "CUSTODIAN UNIT", "scale": 1.0, "y": 0.0,
		"desc": "A cleaning disc that trundles the floor — until it sees you, rears up on four legs and fires.",
		"strengths": ["Disguised as harmless until it stands", "Tough once it unfolds into a walker"],
		"weaknesses": ["Helpless while still a disc — hit it before it rises", "Slow to reposition"],
		"weapons": ["SG-12 Breacher", "GRK-X Devastator", "AR-7 Pulse Rifle"],
	},
	"hunter": {
		"scene": "res://scenes/enemies/hunter.tscn", "name": "HUNTER", "scale": 1.0, "y": 0.0,
		"desc": "A sleek twin-cannon skirmisher that circle-strafes at mid range and rakes you with bursts.",
		"strengths": ["Constant movement — never a still target", "Rapid bolt bursts wear you down"],
		"weaknesses": ["Moderate armour", "Loses you when line of sight breaks"],
		"weapons": ["AR-7 Pulse Rifle", "GEM-2 Twin Rail", "MK-VII Longshot"],
	},
	"reaper": {
		"scene": "res://scenes/enemies/reaper.tscn", "name": "REAPER", "scale": 1.0, "y": 0.0,
		"desc": "A gaunt blade-frame that sprints in and lunges with twin scythe arms.",
		"strengths": ["Extremely fast charge", "Devastating melee lunge"],
		"weaknesses": ["Fragile — drop it before it reaches you", "No ranged option"],
		"weapons": ["SG-12 Breacher", "NV-X Nova Scatter", ".50 Maelstrom"],
	},
	"strider": {
		"scene": "res://scenes/enemies/strider.tscn", "name": "STRIDER", "scale": 1.0, "y": 0.0,
		"desc": "A chicken-walker sentry with a single red eye and a chin gun. Strides to mid range and rakes you.",
		"strengths": ["Accurate bolt bursts at range", "Strafes to keep distance"],
		"weaknesses": ["Spindly legs — staggers under heavy fire", "Loses track behind cover"],
		"weapons": ["MK-VII Longshot", "ARC-9 Gauss Lance", "AR-7 Pulse Rifle"],
	},
	"sniper": {
		"scene": "res://scenes/enemies/sniper.tscn", "name": "SNIPER SENTRY", "scale": 1.0, "y": 0.0,
		"desc": "A long-range turret that charges a beam — a red line marks the shot before it fires.",
		"strengths": ["Hits hard from across the map", "Punishes standing in the open"],
		"weaknesses": ["Slow charge — break line of sight to dodge", "Stationary and exposed"],
		"weapons": ["MK-VII Longshot", "ARC-9 Gauss Lance", ".50 Maelstrom"],
	},
	"seeker": {
		"scene": "res://scenes/enemies/seeker.tscn", "name": "SEEKER", "scale": 1.0, "y": 1.3,
		"desc": "A kamikaze flyer that rushes in and detonates against you. Drop it early.",
		"strengths": ["Fast, direct, and explosive", "Forces you to keep moving"],
		"weaknesses": ["Detonates harmlessly if killed at range", "Low health"],
		"weapons": ["AR-7 Pulse Rifle", "MK-VII Longshot", "NV-X Nova Scatter"],
	},
	"brute": {
		"scene": "res://scenes/enemies/brute.tscn", "name": "BULWARK BRUTE", "scale": 1.0, "y": 0.0,
		"desc": "A walking wall — its frontal shield soaks everything you throw at its face.",
		"strengths": ["Frontal shield negates head-on fire", "Heavy and relentless"],
		"weaknesses": ["Exposed sides and back — flank it", "Slow to wheel around"],
		"weapons": ["SG-12 Breacher", "GRK-X Devastator", "VOID-9 Singularity Cannon"],
	},
	"gunner": {
		"scene": "res://scenes/enemies/gunner.tscn", "name": "GUNNER", "scale": 1.0, "y": 0.0,
		"desc": "A heavy weapons bot with a top-mounted chaingun. After a spin-up it unloads a long suppressive burst.",
		"strengths": ["Brutal sustained fire once spun up", "Armoured front"],
		"weaknesses": ["Telegraphed spin-up — use cover then flank", "Slow and ponderous"],
		"weapons": ["GRK-X Devastator", "ARC-9 Gauss Lance", "GEM-2 Twin Rail"],
	},
	"raptor": {
		"scene": "res://scenes/enemies/raptor.tscn", "name": "RAPTOR", "scale": 0.7, "y": 1.6,
		"desc": "A flying heavy gunner that hovers at range and strafes while raking you with bolt bursts.",
		"strengths": ["Airborne — harder to hit than ground units", "Keeps its distance and pours on fire"],
		"weaknesses": ["Lead it and it drops fast", "Weak armour for a heavy"],
		"weapons": ["MK-VII Longshot", "ARC-9 Gauss Lance", "AR-7 Pulse Rifle"],
	},
	"mender": {
		"scene": "res://scenes/enemies/mender.tscn", "name": "MENDER", "scale": 1.0, "y": 1.5,
		"desc": "A support flyer that beam-heals other robots and flees from you. Kill it FIRST or nothing else dies.",
		"strengths": ["Keeps the whole pack alive", "Runs and hides behind allies"],
		"weaknesses": ["No real offence of its own", "Fragile once cornered"],
		"weapons": ["MK-VII Longshot", "AR-7 Pulse Rifle", "ARC-9 Gauss Lance"],
	},
	"sentinel": {
		"scene": "res://scenes/enemies/sentinel.tscn", "name": "SENTINEL", "scale": 1.0, "y": 0.0,
		"desc": "A four-legged weapons platform — slow, heavily armoured, patient. Plants at range and lobs heavy bolts.",
		"strengths": ["Very tough", "Heavy hitting bolts from afar"],
		"weaknesses": ["Slow to relocate", "Use cover and chip it down"],
		"weapons": ["ARC-9 Gauss Lance", "GRK-X Devastator", "VOID-9 Singularity Cannon"],
	},
	"mauler": {
		"scene": "res://scenes/enemies/mauler.tscn", "name": "MAULER", "scale": 1.0, "y": 0.0,
		"desc": "A slab-bodied brawler with two oversized hammer-fists. Slow but brutally tough — it closes in and slams.",
		"strengths": ["Enormous health pool", "One slam can end you"],
		"weaknesses": ["Slow — kite it endlessly", "Never let it corner you"],
		"weapons": ["GRK-X Devastator", "VOID-9 Singularity Cannon", "SG-12 Breacher"],
	},
	"ravager": {
		"scene": "res://scenes/enemies/ravager.tscn", "name": "RAVAGER", "scale": 0.7, "y": 0.0,
		"desc": "The fierce alpha of the swarm: an armoured bruiser that lumbers, then bounds the length of the arena in a high arc and ground-slams on landing. Punishes standing still.",
		"strengths": ["Heavy armour, near-impossible to stagger", "Leap covers huge distance", "Slam hits a whole radius"],
		"weaknesses": ["The windup before each leap is a clear tell", "Ponderous between bounds — reposition and burn it down"],
		"weapons": ["TPX-9 Tempest Coil", "VOID-9 Singularity Cannon", "OMEGA-X Annihilator"],
	},
	"warmech": {
		"scene": "res://scenes/enemies/warmech.tscn", "name": "WARMECH", "scale": 0.55, "y": 0.0,
		"desc": "A bipedal siege walker with twin shoulder cannons. Enormously armoured and slow; it plants at long range and lobs salvos of heavy plasma shells you have to dodge. The late-game area-denial anchor — break line of sight or flank it.",
		"strengths": ["Colossal armour pool", "Long-range salvos pin you down", "Shrugs off small-arms fire"],
		"weaknesses": ["Slow to turn and reposition", "Telegraphed charge before each salvo", "Flank it while it's committed to a shot"],
		"weapons": ["TPX-9 Tempest Coil", "GRK-X Devastator", "OMEGA-X Annihilator"],
	},
	"dog": {
		"scene": "res://scenes/enemies/dog.tscn", "name": "K-9 HUNTER", "scale": 1.4, "y": 0.0,
		"desc": "A four-legged robot attack-hound. It sprints the gap in a heartbeat, hunts in packs, and lunges in to bite. Fragile — but if one closes, more are right behind it.",
		"strengths": ["Blistering speed — eats distance instantly", "Hunts in packs and flanks", "Low to the ground, hard to track far off"],
		"weaknesses": ["Thin armour — drops to a solid hit", "No ranged attack — kill it before it reaches you"],
		"weapons": ["SG-12 Breacher", "NV-X Nova Scatter", "VK-7 Tesla Projector"],
	},
	"server": {
		"scene": "res://scenes/enemies/server.tscn", "name": "MAITRE-D'", "scale": 1.0, "y": 0.0,
		"desc": "A cafe serving robot whose smile turned to a red glare. It trundles up on its wheeled base and swings its serving trays like cleavers, bashing you off your feet. Slow, but tanky and brutal up close.",
		"strengths": ["Tough chassis — soaks a lot of fire", "Heavy tray-swings knock you back", "Relentless once it has your scent"],
		"weaknesses": ["Slow — kite it in circles", "No ranged option", "Big, easy target for heavy weapons"],
		"weapons": ["GRK-X Devastator", "SG-12 Breacher", ".50 Maelstrom"],
	},
	"alien": {
		"scene": "res://scenes/enemies/alien.tscn", "name": "VOID SENTINEL", "scale": 1.0, "y": 1.4,
		"desc": "An off-world flyer the AI summoned across the dark. Strafes and spits corrosive bio-plasma — its throat flares green before it fires.",
		"strengths": ["Erratic flight, corrosive volleys", "Green throat-flare is your only warning"],
		"weaknesses": ["Juke the orbs and it can't connect", "Falls to sustained fire"],
		"weapons": ["AR-7 Pulse Rifle", "MK-VII Longshot", "GEM-2 Twin Rail"],
	},
	"terminator": {
		"scene": "res://scenes/enemies/terminator.tscn", "name": "TERMINATOR", "scale": 0.85, "y": 0.0,
		"desc": "An elite hunter — relentless, armoured, and smart. It will not stop coming.",
		"strengths": ["Tough and aggressive", "Adapts and pursues"],
		"weaknesses": ["Heavy weapons stagger it", "Focus fire brings it down"],
		"weapons": ["GRK-X Devastator", "ARC-9 Gauss Lance", "VOID-9 Singularity Cannon"],
	},
	"overseer": {
		"scene": "res://scenes/enemies/overseer.tscn", "name": "OVERSEER", "scale": 0.45, "y": 0.0,
		"desc": "A gunship boss — volley fire from above and it summons Seekers to swarm you. Use cover.",
		"strengths": ["Rains volleys from the air", "Summons endless Seeker escorts"],
		"weaknesses": ["Kill the Seekers, then punish its reloads", "Big enough for heavy ordnance"],
		"weapons": ["GRK-X Devastator", "VOID-9 Singularity Cannon", "OMEGA-X Annihilator"],
	},
	"colossus": {
		"scene": "res://scenes/enemies/colossus.tscn", "name": "GOLIATH-IX", "scale": 0.32, "y": 0.0,
		"desc": "A walking siege engine. Bring everything you have — and keep moving.",
		"strengths": ["Massive health and armour", "Area attacks punish standing still"],
		"weaknesses": ["Slow — outmanoeuvre it", "Heavy weapons are the only real answer"],
		"weapons": ["OMEGA-X Annihilator", "GRK-X Devastator", "VOID-9 Singularity Cannon"],
	},
	"smasher": {
		"scene": "res://scenes/enemies/smasher.tscn", "name": "BEHEMOTH-X", "scale": 0.3, "y": 0.0,
		"desc": "A towering humanoid war-mech with a blazing reactor core and two oversized fists. It doesn't shoot — it CHARGES you down and hammers with overhead fist-smashes and ground-quaking slams. Never let it corner you.",
		"strengths": ["Colossal health and armour", "Closes distance in a relentless charge", "Smash and slam hit brutally hard up close"],
		"weaknesses": ["Pure melee — kite it and punish from range", "Telegraphs each smash/slam — read it and dash clear"],
		"weapons": ["OMEGA-X Annihilator", "GRK-X Devastator", "VOID-9 Singularity Cannon"],
	},
	"titan": {
		"scene": "res://scenes/enemies/titan.tscn", "name": "PROMETHEUS-0", "scale": 0.3, "y": 0.0,
		"desc": "The first true AGI, given legs. Artillery, beam, and a ground quake — never stop moving.",
		"strengths": ["Multiple heavy attack patterns", "Quake catches the rooted"],
		"weaknesses": ["Telegraphs each attack — read and dodge", "Punishable between salvos"],
		"weapons": ["OMEGA-X Annihilator", "VOID-9 Singularity Cannon", "GRK-X Devastator"],
	},
	"archon": {
		"scene": "res://scenes/enemies/archon.tscn", "name": "ARCHON", "scale": 0.45, "y": 0.0,
		"desc": "The AGI brain behind every machine you've fought. It hangs shielded and DEPLOYS endless legions.",
		"strengths": ["Invulnerable shield while minions live", "Never stops spawning waves"],
		"weaknesses": ["Wipe each wave to drop the shield", "Exposed core — then put a round through the mind"],
		"weapons": ["OMEGA-X Annihilator", "VOID-9 Singularity Cannon", "GRK-X Devastator"],
	},
}

static func get_entry(type: String) -> Dictionary:
	return ENTRIES.get(type, {})

static func has(type: String) -> bool:
	return ENTRIES.has(type)
