class_name Damage
extends RefCounted
## Shared damage formula from DESIGN_ROADMAP §2.3:
##   raw        = attack * skill_multiplier
##   mitigation = raw * defence / (defence + K)
##   final      = max(1, raw - mitigation)

const K := 100.0


## Raw outgoing damage before mitigation.
static func raw_damage(attack: float, skill_multiplier: float = 1.0) -> float:
	return maxf(0.0, attack) * maxf(0.0, skill_multiplier)


## Damage absorbed by defence. Negative defence is treated as zero.
static func mitigation(raw: float, defence: float, k: float = K) -> float:
	var safe_defence := maxf(0.0, defence)
	var safe_k := maxf(0.0, k)
	if safe_defence <= 0.0 or safe_k <= 0.0:
		return 0.0
	return raw * (safe_defence / (safe_defence + safe_k))


## Final integer damage after mitigation, never below 1.
static func final_damage(
	attack: float,
	defence: float,
	skill_multiplier: float = 1.0,
	k: float = K,
) -> int:
	var raw := raw_damage(attack, skill_multiplier)
	return maxi(1, roundi(raw - mitigation(raw, defence, k)))
