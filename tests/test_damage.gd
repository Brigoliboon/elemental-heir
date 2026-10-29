extends RefCounted
## Validates the shared damage formula from DESIGN_ROADMAP §2.3.


func run(_tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# raw 100, mitigation 100 * (100 / 200) = 50, final 50.
	if Damage.final_damage(100.0, 100.0) != 50:
		failures.append("100 attack vs 100 defence must deal 50")

	# No defence means no mitigation.
	if Damage.final_damage(10.0, 0.0) != 10:
		failures.append("zero defence must deal the raw attack")

	# Damage never drops below 1.
	if Damage.final_damage(1.0, 1000.0) != 1:
		failures.append("damage must clamp to a minimum of 1")

	# Skill multipliers apply before mitigation: raw 200, mitigation 100, final 100.
	if Damage.final_damage(100.0, 100.0, 2.0) != 100:
		failures.append("skill_multiplier must scale raw damage before mitigation")

	# Tuning constant K changes mitigation: raw 100 * (100 / 400) = 25, final 75.
	if Damage.final_damage(100.0, 100.0, 1.0, 300.0) != 75:
		failures.append("a custom K must change the mitigation curve")

	# Negative defence is treated as zero.
	if Damage.final_damage(10.0, -50.0) != 10:
		failures.append("negative defence must not increase damage")

	if not is_equal_approx(Damage.raw_damage(20.0, 1.5), 30.0):
		failures.append("raw_damage must multiply attack by skill_multiplier")
	if not is_equal_approx(Damage.mitigation(100.0, 100.0), 50.0):
		failures.append("mitigation must use defence / (defence + K)")

	return failures
