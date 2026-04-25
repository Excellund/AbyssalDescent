extends Node

# Health bars
const COLOR_HEALTH_BAR_BG := Color(0.08, 0.08, 0.08, 0.92)
const COLOR_ENEMY_HEALTH_FILL := Color(0.9, 0.18, 0.2, 0.96)
const COLOR_PLAYER_HEALTH_FILL := Color(0.18, 0.85, 0.33, 0.96)

# Enemy base render template
const COLOR_BODY_OUTER_GLOW := Color(0.1, 0.02, 0.04, 0.46)
const COLOR_BODY_HORN := Color(1.0, 0.9, 0.9, 0.92)
const COLOR_BODY_EYE := Color(1.0, 0.96, 0.94, 0.9)
const COLOR_BODY_SPIKE := Color(0.95, 0.74, 0.74, 0.7)

# Player colors (cyan theme)
const COLOR_PLAYER_GLOW := Color(0.06, 0.24, 0.42, 0.16)
const COLOR_PLAYER_OUTER := Color(0.03, 0.06, 0.09, 0.46)
const COLOR_PLAYER_BODY := Color(0.15, 0.76, 1.0, 1.0)
const COLOR_PLAYER_CORE := Color(0.08, 0.45, 0.84, 1.0)
const COLOR_PLAYER_LIGHT := Color(0.68, 0.92, 1.0, 0.9)
const COLOR_PLAYER_POINTER := Color(0.97, 0.99, 1.0, 0.98)
const COLOR_PLAYER_EYE := Color(0.98, 1.0, 1.0, 0.95)
const COLOR_PLAYER_WING := Color(0.85, 0.96, 1.0, 0.72)
const COLOR_PLAYER_SPEED_ARC := Color(0.56, 0.89, 1.0, 0.26)
const COLOR_PLAYER_DASH_PHASE := Color(0.5, 1.0, 0.98, 0.24)
const COLOR_PLAYER_DASH_STREAK := Color(0.52, 1.0, 0.95, 0.2)

# Player attack colors
const COLOR_SWING_DEFAULT := Color(0.99, 0.96, 0.68, 0.72)
const COLOR_SWING_RAZOR_WIND := Color(0.58, 0.95, 0.86, 0.82)
const COLOR_SWING_RAZOR_WIND_EXTENDED := Color(0.56, 1.0, 0.86, 0.62)
const COLOR_EXECUTION_RING := Color(1.0, 0.62, 0.34, 0.9)
const COLOR_EXECUTION_PROC := Color(1.0, 0.58, 0.3, 0.86)
const COLOR_EXECUTION_PROC_EXTENDED := Color(1.0, 0.58, 0.3, 0.9)
const COLOR_EXECUTION_PIP_LIT := Color(1.0, 0.56, 0.26, 0.92)
const COLOR_EXECUTION_PIP_DARK := Color(0.48, 0.32, 0.25, 0.55)
const COLOR_EXECUTION_WIND_EXTENDED := Color(1.0, 0.62, 0.34, 0.74)
const COLOR_RUPTURE_WAVE_RING := Color(0.44, 0.96, 1.0, 0.86)
const COLOR_RUPTURE_WAVE_AURA := Color(0.46, 0.96, 1.0, 0.3)

# Player reward overlays
const COLOR_RAZOR_WIND_TRIANGLE := Color(0.56, 1.0, 0.86, 0.8)
const COLOR_RAZOR_WIND_LINE := Color(0.86, 1.0, 0.93, 0.86)

# Damage feedback
const COLOR_DAMAGE_FLASH := Color(0.95, 0.12, 0.12, 1.0)

# Enemy-specific colors (chaser = red)
const COLOR_CHASER_BODY := Color(0.95, 0.18, 0.26, 1.0)
const COLOR_CHASER_CORE := Color(0.62, 0.06, 0.12, 1.0)

# Charger (orange)
const COLOR_CHARGER_BODY := Color(0.95, 0.64, 0.18, 1.0)
const COLOR_CHARGER_CORE := Color(0.74, 0.4, 0.08, 1.0)
const COLOR_CHARGER_CORE_CHARGED := Color(0.86, 0.54, 0.1, 1.0)

# Archer (cyan)
const COLOR_ARCHER_BODY := Color(0.26, 0.74, 0.96, 0.9)
const COLOR_ARCHER_CORE := Color(0.55, 0.92, 1.0, 0.8)
const COLOR_ARCHER_AIM := Color(0.96, 0.74, 0.26, 0.72)
const COLOR_ARCHER_AIM_BRACKET := Color(0.96, 0.74, 0.26, 0.7)
const COLOR_ARCHER_PROJECTILE := Color(0.96, 0.76, 0.28, 0.8)

# Shielder (golden orange)
const COLOR_SHIELDER_BODY := Color(0.96, 0.68, 0.26, 0.9)
const COLOR_SHIELDER_CORE := Color(1.0, 0.82, 0.48, 0.8)
const COLOR_SHIELDER_BODY_WINDUP := Color(1.0, 0.74, 0.3, 1.0)
const COLOR_SHIELDER_BODY_THUMP := Color(1.0, 0.82, 0.38, 1.0)
const COLOR_SHIELDER_CORE_THUMP := Color(1.0, 0.9, 0.56, 0.9)
const COLOR_SHIELDER_SHIELD := Color(0.96, 0.74, 0.34, 0.86)
const COLOR_SHIELDER_SHIELD_OUTLINE := Color(1.0, 0.88, 0.6, 0.7)
const COLOR_SHIELDER_SLAM_WARNING_GLOW := Color(1.0, 0.44, 0.2, 0.18)
const COLOR_SHIELDER_SLAM_WARNING_RING := Color(1.0, 0.8, 0.38, 1.0)
const COLOR_SHIELDER_SLAM_SHOCK_GLOW := Color(1.0, 0.62, 0.28, 0.16)
const COLOR_SHIELDER_SLAM_SHOCK_RING := Color(1.0, 0.9, 0.58, 0.84)

# Boss (dark red)
const COLOR_BOSS_BODY := Color(0.78, 0.15, 0.16, 1.0)
const COLOR_BOSS_BODY_TELEGRAPH := Color(0.95, 0.25, 0.22, 1.0)
const COLOR_BOSS_BODY_ATTACK := Color(1.0, 0.34, 0.18, 1.0)
const COLOR_BOSS_CORE := Color(0.98, 0.45, 0.2, 1.0)
const COLOR_BOSS_CORE_TELEGRAPH := Color(1.0, 0.78, 0.28, 1.0)
const COLOR_BOSS_CORE_ATTACK := Color(1.0, 0.86, 0.34, 1.0)
const COLOR_BOSS_GLOW := Color(0.4, 0.04, 0.06, 0.34)
const COLOR_BOSS_CHARGE_LINE := Color(1.0, 0.84, 0.34, 1.0)
const COLOR_BOSS_CHARGE_LINE_INNER := Color(1.0, 0.9, 0.45, 1.0)
const COLOR_BOSS_NOVA_GLOW := Color(1.0, 0.35, 0.15, 1.0)
const COLOR_BOSS_NOVA_RING := Color(1.0, 0.74, 0.3, 1.0)
const COLOR_BOSS_CLEAVE_FILL := Color(1.0, 0.45, 0.18, 1.0)
const COLOR_BOSS_CLEAVE_OUTLINE := Color(1.0, 0.82, 0.4, 1.0)
