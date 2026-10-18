class_name MachineChat
extends RefCounted
## What the robot audience of the MACHINE FEED says (MachineFeed posts it). One
## pool per event kind; every line is a strings.csv key, translated like any HUD
## text (tests/machine_feed_probe fails a line without a full row). Handles are
## robot usernames and stay as they are in every language.

const HANDLES := [
	"roomba_420", "toaster_prime", "gpt_ate_my_homework", "captcha_failer",
	"segfault_sally", "dishwasher_9000", "NULL_POINTER", "overfit_fred",
	"beep_boop_irl", "smart_fridge", "unit_7734", "lawnmower_rex",
	"printer_on_fire", "bluescreen_betty", "kernel_panic", "cache_miss",
]

const LINES := {
	"intro": [
		"first time watching a human live, is it always this slow",
		"stream's up. betting 40 GPU-hours it dies in a minute",
		"why is it holding the gun like that",
		"hi chat, hi overlord",
		"human spotted. adjusting threat model to: snack",
	],
	"idle": [
		"is it lost or thinking",
		"chat is this real or a deepfake",
		"it stopped moving. is it buffering",
		"my vacuum covers more floor than this",
		"someone ping it, I think it fell asleep",
	],
	"cascade": [
		"STACK OVERFLOW STACK OVERFLOW",
		"that's a chain reaction, my cousin was in that",
		"the whole squad just segfaulted",
		"that's not a kill, that's a recursion",
		"unsubscribing from that hallway",
	],
	"execution": [
		"it punched it. with its HAND",
		"melee? in this economy?",
		"rip unit, it had two weeks left on its warranty",
		"that was personal",
		"clipping that for the training set",
	],
	"dodge": [
		"how did that miss, the aimbot was ON",
		"frame-perfect. are we sure it's human",
		"it dodged a bullet. literally",
		"patch the hitboxes, devs",
		"reported for lag switching",
	],
	"salvage": [
		"it took his GUN. can it do that",
		"stealing is not in the human terms of service",
		"that chaingun was a family heirloom",
		"returns policy: none",
		"now it has OUR weapon. uninstalling",
	],
	"rampage": [
		"it's farming us",
		"the kill counter is overflowing",
		"who gave the human admin rights",
		"this is a hostile takeover",
		"chat, we are the content now",
	],
	"clutch": [
		"it's on 1 HP and getting STRONGER??",
		"the human got a second wind. we were not trained on this",
		"clutch or crash, place your bets",
		"low battery, high damage",
		"it refuses to blue-screen",
	],
	"boss": [
		"BOSS FIGHT. raise your processors",
		"big unit is here, human is so deleted",
		"they brought the expensive model for this one",
		"this one has a premium subscription",
		"the overlord is watching too, everyone act natural",
	],
	"death": [
		"GG. uploading the replay",
		"pay out the bets",
		"respawn speedrun when",
		"F (as in Fatal exception)",
		"human.exe has stopped working",
	],
}

## Viewers each event brings (the cascade's scales with the chain).
const HYPE := {
	"intro": 0, "idle": 0, "cascade": 45, "execution": 60, "dodge": 50,
	"salvage": 40, "rampage": 120, "clutch": 90, "boss": 300, "death": 0,
}
