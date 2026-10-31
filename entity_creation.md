Step 2: Create the Data Blueprint (enemy_data.gd)

1. In your bottom-left FileSystem dock, right-click res:// and choose Create Folder. Name it resources.
2. Right-click your new resources folder, select New -> Script.
3. Set Inherits to Resource, set Template to Base: Empty, and set Path to res://resources/enemy_data.gd. Click Create.
4. Paste this code inside it and save (Ctrl + S):
gdscript
extends Resource
class_name EnemyData

@export var enemy_name: String = "Goblin"
@export var max_health: int = 100
@export var move_speed: float = 200.0
@export var attack_damage: int = 15
Use code with caution.

Step 3: Create your Configuration File (goblin.tres)

1. Right-click your resources folder in the FileSystem dock, select New -> Resource...
2. Search for EnemyData, select it, and click Create.
3. Name the file goblin.tres and click Save.
4. Click goblin.tres. In the right-side Inspector dock, fill out your values (Name: Goblin, Health: 60, Speed: 220, Damage: 15). Save it.

Step 4: Create and Save the Node Layout (mob.tscn)

1. Right-click res:// in the FileSystem dock and create a folder named entities. Right-click entities and create a subfolder named enemies.
2. At the top left of Godot, click Scene -> New Scene.
3. In the Scene panel on the left, click Other Node, select CharacterBody2D, and rename it to Mob.
4. Go to the top menu and select Scene -> Save Scene As... Save it inside res://entities/enemies/ as mob.tscn.

Step 5: Configure the Mob Layout & Child Nodes

Add your sub-nodes to the Mob scene root so your hierarchy matches this exactly:
• 📦 Mob (CharacterBody2D)
	• 🔹 CollisionShape2D (Environment collision)
	• 🔹 AnimatedSprite2D (Visuals & Animations)

Set your Node Collision Properties in the Inspector:

Click Mob (Root), look at the Inspector under Collision:
• Layer: Check 3 (Enemies)
• Mask: Check 1 (World)
Click CollisionShape2D, go to the Inspector under Shape, click [empty] and choose New CapsuleShape2D (or Circle). Resize it over your character center.

Step 6: Fix Your Animation Looping Toggles

1. Click your AnimatedSprite2D node. Look at the Inspector under Sprite Frames, click [empty] ➔ New SpriteFrames.
2. Click the newly created SpriteFrames box to open the animation panel at the bottom center of your screen.
3. Create two animations: "default" and "attack". Add your sprite sheets or frames to them.
4. The Critical Fix: Click on your "attack" animation name in that bottom panel. Turn OFF the little looping arrow toggle icon next to the speed box. Click your "default" animation and make sure its looping arrow icon is turned ON.

Step 7: Create and Attach the Script to the Sprite

Since your script targets animation states directly by extending AnimatedSprite2D, we attach this logic directly to the sprite node.
1. Right-click your AnimatedSprite2D node in your scene tree and click Attach Script.
2. Set Inherits to AnimatedSprite2D, set Template to Object: Empty, and change the path to res://entities/enemies/mob_animations.gd. Click Create.
3. Paste this exact script inside it and save:
gdscript
extends AnimatedSprite2D

@export var attack_chance: float = 0.02  # Approx 2% chance per frame

var _is_attacking: bool = false

func _ready() -> void:
	# Listen for when an animation finishes playing
	animation_finished.connect(_on_animation_finished)
	play("default")

func _process(delta: float) -> void:
	# Guard clause: Stop running frame loops if an attack sequence is active
	if _is_attacking:
		return
		
	# Roll the dice to see if an attack triggers
	if randf() <= attack_chance:
		_is_attacking = true
		play("attack")

func _on_animation_finished() -> void:
	# When the non-looping attack ends, clean up state and revert to default
	if animation == "attack": 
		_is_attacking = false
		play("default")
Use code with caution.
Save your scene layout using Ctrl + S. Your architecture is now clean, modular, properly split across files, and protected against frame-loop stuttering and looping glitches.
Now that the logic, data configs, and animations are completely synchronized, let me know:
• Do you want to see how to code a Movement Component on the root Mob node next?
