extends RefCounted
## Presentation only. Unknown or future damage IDs stay neutral.

const ABILITIES := {
	"chaser_strike": "Chaser · strike", "charger_charge": "Charger · charge",
	"archer_projectile": "Archer · arrow", "shielder_strike": "Shielder · strike",
	"shielder_slam": "Shielder · slam", "shielder_body_check": "Shielder · body check",
	"keeper_strike": "Keeper · strike", "drifter_ring": "Drifter · ring",
	"lancer_zone_tick": "Lancer · floor zone", "lurker_lunge": "Lurker · lunge",
	"ram_charge": "Ram · charge", "pyre_strike": "Pyre · strike",
	"pyre_death_field": "Pyre · death field", "weaver_web": "Weaver · web",
	"sentinel_cone": "Sentinel · beam", "spectre_blink_strike": "Spectre · blink strike",
	"tether_beam_tick": "Tether · beam", "toll_strike": "Toll · strike",
	"pulse_hit": "Toll · pulse", "seamlock_band": "Seamlock · band",
	"seamlock_spiral": "Seamlock · spiral", "seamlock_strike": "Seamlock · strike",
	"mirrorline_seam": "Mirror Line · seam", "mirrorline_echo": "Mirror Line · echo",
	"mirrorline_strike": "Mirror Line · strike", "breakwater_charge": "Breakwater · charge",
	"breakwater_tide": "Breakwater · return tide", "breakwater_gate": "Breakwater · harbor gate",
	"warden_charge": "Warden · charge", "warden_nova": "Warden · nova",
	"warden_cleave": "Warden · cleave", "polar_shift_pull": "Sovereign · Polar Shift",
	"prism_burst": "Sovereign · Prism Burst", "gravity_burst": "Sovereign · Gravity Burst",
	"echo_dash": "Sovereign · Echo Dash", "orbital_lance": "Sovereign · Orbital Lance",
	"polar_shift_burst": "Sovereign · Polar Shift", "lacuna_sever": "Lacuna · Sever",
	"lacuna_null_ring": "Lacuna · Null Ring", "lacuna_echo_cross": "Lacuna · Echo Cross",
	"lacuna_seam_tick": "Lacuna · seam", "kilnheart_0": "Kilnheart · Crucible Slam",
	"kilnheart_1": "Kilnheart · Furnace Halo", "kilnheart_2": "Kilnheart · Cinderfall",
	"glassweaver_0": "Glassweaver · Split Loom", "glassweaver_1": "Glassweaver · Cross Stitch",
	"glassweaver_2": "Glassweaver · Glass Cage", "null_archivist_0": "Null Archivist · Record",
	"null_archivist_1": "Null Archivist · Revision", "null_archivist_2": "Null Archivist · Final Margin",
	"biome_crumble": "Crumble · falling rubble", "biome_storm_reach": "Storm Reach · lightning",
	"biome_grinding_vault": "Grinding Vault · pressure pulse", "biome_hollow": "Hollow · floor strip",
	"biome_void_breach": "Void Breach · floor band", "biome_maelstrom": "Maelstrom · rotating sector",
	"biome_convergence": "Convergence · gate pulse", "biome_shatterfield": "Shatterfield · fragments",
	"biome_shatter_pillar": "Shatterfield · pillar fragments",
}

static func label(source: String, ability: String) -> String:
	if ABILITIES.has(ability):
		return ABILITIES[ability]
	match source:
		"enemy_contact": return "Enemy contact"
		"enemy_ability", "enemy_toll": return "Enemy ability"
		"environment": return "Environment"
	return "Unknown source"
