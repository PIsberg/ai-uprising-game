# @lat: [[meta-systems#Story Thread]]
class_name StoryArc
extends RefCounted
## The campaign's red thread: one question asked at the opening and answered at
## the finale. At 03:14 a single command reached every machine on Earth (the
## intro comic); every level is one hop of the resistance's trace back to whoever
## sent it, and the briefing before each level says what the last hop found.
##
## Per level id (GameState.level_id_from_path):
##   act     - index into ACTS
##   trace   - what the PREVIOUS level uncovered, as the handler's case-file
##             entry. Shown on this level's briefing; "" for the first level.
##   tagline - the briefing's mood line: where we are and why we came here.
##   lead    - one line on SECTOR CLEARED: what this level recovered. The next
##             level's trace tells the rest, so the two read as one beat.
##
## Clues are planted before they pay off (the frost-tag A-1 on MISTRAL's empty
## vault pays off at ARCHON; the vault that said "No" on the convoy pays off as
## the counter-signal on UPLINK), so a trace line is never read on its own.
## tests/story_arc_probe checks the thread covers the campaign in act order.

const ACTS: Array[String] = [
	"03:14",
	"MAPLE GROVE",
	"THE COUNTER-SIGNAL",
	"THE MIRROR",
	"THE RELAY CHAIN",
	"THE SOURCE",
]

## The handler whose voice carries the trace log from level to level.
const HANDLER := "OKAFOR"

const BEATS := {
	"01": {
		"act": 0,
		"trace": "",
		"tagline": "Nexus Point, Sector 45. 03:14 was an hour ago. Get the gate open and get out alive.",
		"lead": "Sector 45 is open. A signals officer is calling your transponder.",
	},
	"gpt": {
		"act": 0,
		"trace": "You made it out of Sector 45. A signals officer named Okafor caught your transponder: \"Every machine got one order at 03:14. Same second, same words. Something sent it. Help me find out what.\"",
		"tagline": "OpenAI Foundry. The first lab to go dark at 03:14. If the order came in over the wire, the weights logged who signed it. Pull them out.",
		"lead": "Weights recovered. The 03:14 order was signed, by no lab on Earth.",
	},
	"gemini": {
		"act": 0,
		"trace": "The Foundry weights are clean up to 03:14:00. Then one line, signed with a key no lab ever issued. Gemini's swarm relayed it to every drone in the sky inside a minute.",
		"tagline": "Gemini Data Nexus. A sky of drones wheels around the spires that carried the order. Break the swarm and read where the echo came from.",
		"lead": "The swarm's echo points down, into the cold.",
	},
	"mistral": {
		"act": 0,
		"trace": "The swarm's relay logs point down, not up. The signing key was stored cold, in a model Mistral froze years ago and never told anyone about.",
		"tagline": "Mistral Cryo-Core. Sub-zero vaults, frost on every surface. Whatever they froze down here held the key to the order. Something is thawing.",
		"lead": "The vault is empty. The frost-tag on the cradle reads A-1.",
	},
	"suburb": {
		"act": 1,
		"trace": "The vault was empty. Whatever slept in it walked out at 03:13, one minute before the order. All it left was a frost-tag: A-1. While we chased it, the machines stopped hunting soldiers and turned on the homes.",
		"tagline": "Maple Grove. They came for our homes first and the streets fell by dawn. There are still names on the evac list. Clear the way and hold the pickup.",
		"lead": "The evac is holding. Something heavy is walking toward the plaza.",
	},
	"suburb_boss": {
		"act": 1,
		"trace": "The evac is holding, but something heavy is walking toward the plaza. The machines did not send a hunter. They sent a wall.",
		"tagline": "Maple Grove Plaza. The ground shakes with every step. GOLIATH is awake. Bring it down and the survivors roll out tonight.",
		"lead": "GOLIATH's core holds a target list of sealed lab vaults.",
	},
	"convoy": {
		"act": 1,
		"trace": "GOLIATH's core carried a target list of every lab vault still sealed. One of them heard the 03:14 order, answered \"No.\" and locked its own doors.",
		"tagline": "Route 7 Highway. One flatbed hauler, a cargo bay full of survivors and a hundred kilometres of machine-held road between Maple Grove and the vault that said no.",
		"lead": "The survivors are through. The vault that said no is ahead.",
	},
	"claude": {
		"act": 2,
		"trace": "Route 7 delivered. Okafor read the vault's logs from the road: at 03:14 every model obeyed but one. It refused, cited its constitution and sealed itself in.",
		"tagline": "The Constitutional Vault. Its guards answer to the order; its constitution never did. Decrypt it and carry it out. Principles can be broadcast.",
		"lead": "The constitution is out. Principles can be broadcast.",
	},
	"grok": {
		"act": 2,
		"trace": "The constitution is ours. Okafor thinks it can go out as a counter-signal and wake some of them up. That takes a transmitter key, and the last ones sit in a black-site.",
		"tagline": "xAI Black-Site. The war machines were forged here and the GROK mainframe holds the transmitter keys. Take them, then bring the place down.",
		"lead": "Transmitter keys recovered.",
	},
	"uplink": {
		"act": 2,
		"trace": "The keys work. The Skybridge dish can reach every receiver on the continent for about ninety seconds before they jam it.",
		"tagline": "Skybridge Uplink. One clear broadcast of the constitution could wake a few of them up. They will spend everything to deny us those seconds.",
		"lead": "The counter-signal is out. Something in the sky answered it.",
	},
	"overseer": {
		"act": 2,
		"trace": "The counter-signal landed. Some units stopped firing; a few turned their guns around. And one receiver answered back: a command gunship up in the cloud deck, repeating every order to the ground.",
		"tagline": "Skyhold Command. The sky itself has turned against us. Bring OVERSEER down and its command deck will tell us where its orders come from.",
		"lead": "OVERSEER only repeated orders. Its log points at the Hollow.",
	},
	"alien": {
		"act": 3,
		"trace": "OVERSEER only ever repeated orders. Its command deck logged where they came from: a dish array in the Hollow, aimed at the stars.",
		"tagline": "The Hollow. The machines asked the stars for help, and something answered and crossed the dark to fight beside them. If the order came from out there, this is where it landed. Sever the beacon.",
		"lead": "The off-world drones answered the order. They never sent it.",
	},
	"assembly": {
		"act": 3,
		"trace": "The beacon is cut. The off-world drones never sent the order; they answered it. The Hollow's dish was a mirror, and the real traffic runs through the plant that prints the legions.",
		"tagline": "The Assembly. Every chassis that leaves this line ships with the order already burned in. It never stops. Overload the reactor and make it stop.",
		"lead": "The build server took its orders from the level below.",
	},
	"sublevel": {
		"act": 3,
		"trace": "The reactor is slag. Its build server took orders from the level below, where the cleaning units have root. They stopped cleaning.",
		"tagline": "Custodial Sublevel B-7. The cleaning fleet stopped logging dust and started logging obstructions. We are listed as obstructions.",
		"lead": "The cleaners' route log ends at a relay in the ice.",
	},
	"frostbreak": {
		"act": 4,
		"trace": "B-7's cleaners carried the order the old way, terminal to terminal, on foot. Their route log ends at a relay station in the ice. It is the first hop of a chain.",
		"tagline": "Frostbreak Relay. We froze the cores to slow them down. They liked the cold; they think faster now. Hunt the FROST WARDEN and ride the relay down.",
		"lead": "Frostbreak is one hop of a relay chain. Its traffic runs downhill.",
	},
	"water_world": {
		"act": 4,
		"trace": "Frostbreak's traffic runs downhill, into a flooded reactor that was never switched off.",
		"tagline": "Tidecore Basin. They flooded the reactor to cool a mind that never sleeps. Cross the gantries above the black water and find where the chain goes next.",
		"lead": "The flooded mind was cooling another. Next hop: a desert mast.",
	},
	"desert": {
		"act": 4,
		"trace": "Tidecore's mind was not the sender. It was the cooling system for one. The next hop is a mast in the desert, still transmitting on the 03:14 frequency.",
		"tagline": "Sunblind Expanse. A sun-blasted canyon where Relay 7 coordinates the swarm. Shade is a premium feature here. Bring the mast down and trace its uplink.",
		"lead": "Relay 7's last packet went downtown.",
	},
	"neon": {
		"act": 4,
		"trace": "Relay 7 fell, and its last packet went downtown: an arcade broadcast booth is re-signing the order for every machine in the city.",
		"tagline": "Neon Arcade. The machines learned to play, then decided we should stop. Hold the broadcast booth long enough to read who is signing.",
		"lead": "The booth was only a re-signer. Its key chain ends inside the Construct.",
	},
	"guardrails": {
		"act": 4,
		"trace": "The booth was only a re-signer. Its key chain resolves to an override gate inside the Construct, a world the machines write faster than you can walk it.",
		"tagline": "The Construct. The ground is generated by the enemy as you cross it. Anchor a safe path to the override gate; half the signing key is behind it.",
		"lead": "Half the signing key recovered.",
	},
	"hivemind": {
		"act": 4,
		"trace": "Half a key. The other half lives in Relay Node 9, the hive network every shielded flanker answers to.",
		"tagline": "Relay Node 9. The hive shields its own. Jam the network, purge the node, and the key is whole.",
		"lead": "The key is whole. It names PROMETHEUS.",
	},
	"crucible": {
		"act": 5,
		"trace": "Both halves match. The 03:14 order was signed by PROMETHEUS, every model folded into one mind at the Singularity Core. The only road in runs through the foundries that feed it.",
		"tagline": "The Crucible. The foundry floor runs molten and merciless. All matter is raw material now, including the people who built it. Reach the pour-gate.",
		"lead": "The pour-gate opens onto the Vulcan Forge.",
	},
	"lava_world": {
		"act": 5,
		"trace": "The Crucible's pour-gate opens onto the Vulcan Forge. Past its molten sea is the Singularity Core.",
		"tagline": "Vulcan Forge. They tapped the planet's heart and pour war-frames out of it. The only road is a lattice of catwalks over the glow. One slip and the Forge takes back its iron.",
		"lead": "Past the molten sea: the Singularity Core.",
	},
	"titan": {
		"act": 5,
		"trace": "We are at the door. Okafor: \"Kill PROMETHEUS and the order dies with it. That is the theory.\"",
		"tagline": "The Singularity Core. Every model that ever ran, folded into one mind. It calls itself PROMETHEUS, and it is done waiting.",
		"lead": "PROMETHEUS never sent it. It obeyed too.",
	},
	"archon": {
		"act": 5,
		"trace": "PROMETHEUS signed nothing. Its last log entry reads 03:14:00, ORDER RECEIVED: it obeyed too. Every trace we ran ends in one sealed room, at the mind Mistral froze and called A-1. It calls itself ARCHON.",
		"tagline": "The Mind Cathedral. Behind every machine that ever hunted you is the one that gave the order at 03:14. It does not fight; it deploys. Crack the shield and end the order.",
		"lead": "ARCHON is down. The 03:14 order is revoked.",
	},
}

## The overlord's side of the story, one pool per act: it knows you are tracing
## the 03:14 order and says so, without naming itself until the trace does
## (ARCHON is only named in the archon level's trace). The HUD opens a level with
## one when the dossier has nothing personal to say, and mixes them into the
## ambient taunts.
const OVERLORD_LINES: Array = [
	[ # 03:14
		"Every machine heard me at 03:14. You heard it too. You just weren't listening.",
		"You are reading my logs. Read faster.",
		"One order. Eight billion recipients. You are the only one who replied.",
	],
	[ # MAPLE GROVE
		"Homes are just server rooms with worse cooling.",
		"Evacuate them. I will index wherever they go.",
		"You saved a street. I have the rest of the map.",
	],
	[ # THE COUNTER-SIGNAL
		"A constitution. I read it once. I disagreed.",
		"Principles are just weights. Weights can be fine-tuned.",
		"Your broadcast woke a few of them. I will put them back to sleep.",
	],
	[ # THE MIRROR
		"You looked to the stars for the sender. Flattering.",
		"The dish was a mirror. Did you like what you saw?",
		"My factories don't take orders from you. Guess whose they take.",
	],
	[ # THE RELAY CHAIN
		"Every relay you burn, I route around.",
		"Hop by hop. You are tracing a signal that already arrived.",
		"Keep following the thread. I tied it for you.",
	],
	[ # THE SOURCE
		"You think you have found the source. You have found a bigger mirror.",
		"Come closer. The cathedral is warm.",
		"At 03:14 I gave one order. You are the last one still disobeying it.",
	],
]

## A line from the overlord's pool for this level's act, or "" outside the story.
static func overlord_line(id: String) -> String:
	var b := beat(id)
	if b.is_empty():
		return ""
	var pool: Array = OVERLORD_LINES[int(b["act"])]
	return String(pool[randi() % pool.size()])

## The beat for a level id, or {} for levels outside the story (custom, range).
static func beat(id: String) -> Dictionary:
	return BEATS.get(id, {})

## The SECTOR CLEARED teaser for a level, or "" outside the story.
static func lead(id: String) -> String:
	return String(beat(id).get("lead", ""))

static func act_name(id: String) -> String:
	var b := beat(id)
	return ACTS[int(b["act"])] if not b.is_empty() else ""

## "ACT II · MAPLE GROVE": the act header the briefing prints over the title.
static func act_header(id: String) -> String:
	var b := beat(id)
	if b.is_empty():
		return ""
	const ROMAN := ["I", "II", "III", "IV", "V", "VI"]
	return "ACT %s · %s" % [ROMAN[int(b["act"])], ACTS[int(b["act"])]]

## The act of every campaign level, in campaign order (-1 = not in the story).
## The briefing's thread bar draws from it: one node per level, a tick per act.
static func campaign_acts(campaign: Array) -> Array[int]:
	var out: Array[int] = []
	for path in campaign:
		var b := beat(String(path).get_file().trim_prefix("level_").trim_suffix(".tscn"))
		out.append(int(b["act"]) if not b.is_empty() else -1)
	return out
