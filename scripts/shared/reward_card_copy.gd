extends RefCounted
## The explanatory card paragraph is separate from its numeric upgrade line.
## Semantic spans are authored explicitly so wording and keyword identity agree.

const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const MAX_EXPLANATION_CHARACTERS := 175

static func explanation(power_id: String, level: int, prismatic: bool = false) -> String:
	return KEYWORDS.format_text(_authored_explanation(power_id, level, prismatic))

static func _authored_explanation(power_id: String, level: int, prismatic: bool) -> String:
	match power_id:
		"razor_wind":
			return "Each {kw:attack} adds a cutting arc beyond your normal melee reach. The arc damages distant foes without striking nearby enemies a second time."
		"execution_edge":
			if prismatic:
				return "Every {kw:attack} becomes an execution strike that deals much more damage. There is no longer a weaker swing between execution strikes."
			return "Every few {kw:attack|Attacks}, an execution strike deals much more damage. Misses still advance the count, so you can prepare it before closing in."
		"rupture_wave":
			if level >= 3:
				return "{kw:attack_hit|Attack hits} release a damaging, {kw:slow|Slowing} {kw:burst} that can spread once as a smaller {kw:burst}. Each foe takes Rupture Wave damage only once per {kw:attack}."
			if level >= 2:
				return "{kw:attack_hit|Attack hits} release a {kw:burst} that damages and {kw:slow|Slows} nearby foes. Each enemy can take Rupture Wave damage only once from the same {kw:attack}."
			return "{kw:attack_hit|Attack hits} release a damaging {kw:burst} around the struck foe. Each enemy can take Rupture Wave damage only once from the same {kw:attack}."
		"aegis_field":
			return "A recurring {kw:burst} {kw:slow|Slows} nearby foes and briefly reduces the damage you take. The pulse activates automatically and does not deal damage."
		"hunters_snare":
			if level >= 3:
				return "{kw:attack_hit|Attack hits} {kw:slow} foes, and all your damage is stronger against already {kw:slow|Slowed} enemies. All {kw:slow} effects you apply now last twice as long."
			if level >= 2:
				return "{kw:attack_hit|Attack hits} {kw:slow} foes. All your damage is stronger against enemies that were already {kw:slow|Slowed}, including damage from {kw:field|Fields}, {kw:projectile|Projectiles} and {kw:echo|Echoes}."
			return "{kw:attack_hit|Attack hits} {kw:slow} foes. Your {kw:attack|Attacks} deal more damage to already {kw:slow|Slowed} targets; applying {kw:slow} with this hit does not boost that same hit."
		"phantom_step":
			return "{kw:dash} through foes to damage and {kw:slow} them, hitting each enemy once during that {kw:dash}. {kw:recoil} and {kw:orbit} do not trigger this effect."
		"riftpunch":
			if level >= 3:
				return "Finishing a {kw:dash} empowers your next {kw:attack_hit} with bonus damage, {kw:slow}, a damaging {kw:burst} and brief contact protection. The opening expires if unused."
			if level >= 2:
				return "Finishing a {kw:dash} readies your next {kw:attack_hit} for bonus damage, {kw:slow} and brief protection from enemy contact. Land it before the opening expires."
			return "Finishing a {kw:dash} readies your next {kw:attack_hit} for bonus damage and brief protection from enemy contact. Land it before the opening expires."
		"reaper_step":
			if level >= 3:
				return "Your {kw:dash} moves faster and farther. {kw:kill|Kills} refresh it, quick {kw:kill} chains can store one extra {kw:dash}, and chain {kw:kill|Kills} grant brief contact protection."
			if level >= 2:
				return "Your {kw:dash} moves faster and farther, and {kw:kill|Kills} refresh it. After a {kw:kill} refreshes {kw:dash}, another quick {kw:kill} can store one extra {kw:dash}."
			return "Your {kw:dash} moves faster and farther. {kw:kill|Killing} a foe immediately refreshes its cooldown, letting you {kw:dash} again without waiting for it to recharge."
		"static_wake":
			if level >= 3:
				return "{kw:dash} leaves an {kw:electric} {kw:field} that damages and then {kw:slow|Slows} foes in your trail. Only two trails remain; overlapping trails do not deal extra damage."
			return "{kw:dash} leaves an {kw:electric} {kw:field} that damages foes in your trail. Only two trails remain, and overlapping trails do not deal extra damage."
		"storm_crown":
			if level >= 2:
				return "Your damage charges {kw:electric} chain lightning; already {kw:slow|Slowed} foes add one jump. Each foe counts once per action, with at most one chain per action."
			return "Your damage charges {kw:electric} chain lightning. Each foe charges it once per action, and one action can release only one chain."
		"wraithstep":
			if level >= 3:
				return "{kw:dash} {kw:mark|Marks} foes. An {kw:attack_hit} on an already {kw:mark|Marked} foe releases one {kw:burst} per {kw:attack}, then spreads damage through up to three more {kw:mark|Marked} foes."
			if level >= 2:
				return "{kw:dash} {kw:mark|Marks} foes. An {kw:attack_hit} against an already {kw:mark|Marked} foe releases a damaging {kw:burst} around them, at most once per {kw:attack}."
			return "{kw:dash} past foes to {kw:mark} them, making them take more damage from all players. {kw:mark|Marks} expire with time; dealing damage does not consume them."
		"voidfire":
			return "Connected {kw:attack|Attacks} build Heat. High Heat strengthens your {kw:attack|Attacks}; overheating releases a damaging {kw:burst}, empties the Heat bar and briefly locks {kw:attack|Attacks}."
		"dread_resonance":
			return "{kw:attack_hit|Attack hits} {kw:mark} foes and build stacks on each enemy, increasing your damage while that foe is {kw:mark|Marked}. Changing targets does not erase those stacks."
		"bloodvow":
			return "While your health is low, every {kw:attack} deals more damage. The bonus ends above the health threshold; staying lower does not increase it further."
		"eclipse_mark":
			return "{kw:kill|Kills} {kw:mark} nearby foes, increasing the damage they take from all players. Only the strongest {kw:mark} applies, and damage does not consume it."
		"fracture_field":
			return "{kw:kill|Kills} send damaging fault-line {kw:burst|Bursts} from the defeated enemy, {kw:slow|Slowing} foes they cross. Enemies killed by Fracture cannot create another Fracture."
		"farline_volley":
			if level >= 3:
				return "Outer {kw:attack_hit|attack hits} build stacks that widen and strengthen {kw:attack|Attacks} and can {kw:slow} foes. {kw:dash|Dashing} clears all stacks, releasing a {kw:burst} only if the stack bar was full."
			if level >= 2:
				return "Outer {kw:attack_hit|attack hits} build stacks that widen and strengthen {kw:attack|Attacks}. With enough stacks, these hits also {kw:slow} foes. {kw:dash|Dashing} clears the stacks."
			return "{kw:attack_hit|Attack hits} near the edge of your reach build Volley stacks, making {kw:attack|Attacks} wider and stronger. {kw:dash|Dashing} clears every stack."
		"sigil_chain":
			if level >= 3:
				return "Four {kw:attack_hit|attack hits} arm a damaging, {kw:slow|Slowing} {kw:field} for your next connected {kw:attack}. Placing more sigils before the chain fades makes their damage stronger."
			if level >= 2:
				return "Four {kw:attack_hit|attack hits} charge a sigil. Your next connected {kw:attack} places a {kw:field} that repeatedly damages and {kw:slow|Slows} nearby foes."
			return "Four {kw:attack_hit|attack hits} charge a sigil. Your next connected {kw:attack} places a {kw:field} that repeatedly damages nearby foes; automatic effects cannot charge it."
		"blast_drive":
			if level >= 3:
				return "Hold {kw:attack}, aim, then release a forward {kw:burst} with backward {kw:recoil}. Store two charges and steer {kw:recoil} with movement input; quick taps still strike."
			if level >= 2:
				return "Hold {kw:attack}, aim, then release a forward {kw:burst} with backward {kw:recoil}. You can store two charges for consecutive launches; quick taps still strike."
			return "Hold {kw:attack} after a swing, aim, then release a forward {kw:burst} with backward {kw:recoil}. Quick taps still attack immediately; each blast spends one charge."
		"razor_orbit":
			if level >= 3:
				return "Aim and hold {kw:dash} to {kw:orbit} a foe or column for 1.4 seconds; release to depart. If the foe anchor dies, aim at another to transfer once, up to 2.4 seconds total."
			if level >= 2:
				return "Aim at a foe or column and hold {kw:dash} through its end to {kw:orbit} the anchor with cutting strikes. Release to depart, or leave after 1.4 seconds."
			return "Aim at a foe and keep {kw:dash} held after it ends to {kw:orbit} them, cutting as you move. Release to depart, or leave automatically after 1.4 seconds."
		"returning_crescent":
			if level >= 3:
				return "{kw:attack|Attacks} throw returning {kw:projectile|Projectiles} that bounce once off walls or obstacles outward. Keep up to two in flight; each hits a foe once outward and once returning."
			if level >= 2:
				return "{kw:attack|Attacks} throw {kw:projectile|Projectiles} that return to your current position, hitting each foe once each way. Keep up to two in flight and move to guide their return."
			return "{kw:attack|Attacks} throw a {kw:projectile} that returns to your current position. Move to guide it through foes, striking each once outward and once returning. One at a time."
		"wardens_verdict":
			return "Each sequence of four {kw:attack_hit|attack hits} grows stronger and ends in a damaging {kw:burst}. The count resets after 2.2 seconds without an {kw:attack_hit}."
		"lacuna_echo":
			return "{kw:kill|Kills} leave one {kw:pull|pulling}, damaging well, replacing the last. Foes in any {kw:field} you own take more damage from you; overlapping {kw:field|Fields} do not stack the bonus."
		"sovereign_tempo":
			return "Connected {kw:attack|Attacks} build temporary move speed. Finishing a {kw:dash}, {kw:recoil} or {kw:orbit} spends those stacks in a damaging {kw:burst}; connecting refunds {kw:dash} cooldown."
		"pillar_convergence":
			return "Connected {kw:attack|Attacks} build toward a pulsing {kw:field} that follows you and damages nearby foes. It cannot charge again until the active {kw:field} ends."
		"unbroken_oath":
			return "Gain damage resistance. {kw:attack_hit|Attack hits} fill Oath faster when you strike several foes; filling the bar empowers your next {kw:attack}, which spends it even if you miss."
		"edict_of_the_court":
			return "{kw:kill|Kills} release a force {kw:burst} that {kw:push|Pushes} nearby foes away from the defeated enemy. The {kw:push} deals no damage by itself."
		"null_corridor":
			return "{kw:dash} leaves a {kw:field} that damages foes and {kw:push|Pushes} them sideways. Each trail can affect the same enemy again after half a second."
		"ruinous_impact":
			return "{kw:attack_hit|Attack hits} {kw:launch} foes, and {kw:push|Pushes} or {kw:pull|Pulls} can also arm them to {kw:burst} on {kw:impact}. Each {kw:launch} bursts once; immovable foes compress and burst in place."
		"sovereigns_double":
			if level >= 2:
				return "Finishing a {kw:dash}, {kw:recoil} or {kw:orbit} leaves a shade that {kw:echo|Echoes} your next two {kw:attack|Attacks} at reduced damage. Only your latest shade remains; {kw:echo|Echoes} spend no extra resources."
			return "Finishing a {kw:dash}, {kw:recoil} or {kw:orbit} leaves a shade that {kw:echo|Echoes} your next {kw:attack} at reduced damage. Only your latest shade remains; {kw:echo|Echoes} spend no extra resources."
	return ""
