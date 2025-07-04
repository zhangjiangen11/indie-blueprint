## A useful component to apply camera movement for a first person view
@icon("res://components/motion/3D/first_person/camera/camera_controller_3d.svg")
class_name IndieBlueprintFirstPersonCameraController extends Node3D

@export var actor: IndieBlueprintFirstPersonController
@export var camera_pivot: Node3D
@export var camera: Camera3D
## 0 Means the rotation on the Y-axis is not limited
@export_range(0, 360.0, 0.5, "degrees") var camera_vertical_limit: float = 89.0
## 0 Means the rotation on the X-axis is not limited
@export_range(0, 360.0, 0.5, "degrees") var camera_horizontal_limit: float = 0.0
@export_category("Fov")
@export_range(0, 10.0, 0.01) var fov_smooth_factor: float = 1.2 
@export var fov_lerp_speed: float = 6.0
@export_group("Swing head")
@export var swing_head_enabled: bool = true
@export_range(0, 360.0, 0.01, "degrees") var swing_rotation_degrees: float = 1.5
@export var swing_lerp_factor: float = 5.0
@export var swing_lerp_recovery_factor: float = 7.5
@export_group("Bob head")
@export var bob_enabled: bool = true
@export var bob_head: Node3D:
	set(value):
		if value != bob_head:
			bob_head = value
			
			if bob_head != null:
				original_head_bob_position = bob_head.position
@export_range(0, 10.0, 0.01) var bob_frequency: float = 2.4
@export_range(0, 0.4, 0.01) var bob_amplitude: float = 0.08

@onready var current_vertical_limit: float:
	set(value):
		current_vertical_limit = clampf(value, 0.0, rad_to_deg(TAU))
		
@onready var current_horizontal_limit: float:
	set(value):
		current_horizontal_limit = clampf(value, 0.0, rad_to_deg(TAU))

@onready var root_node: Window = get_tree().root

enum RotationState {
	NoRotation,
	RotationZ
}

var last_mouse_input: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 3.0
var controller_joystick_sensitivity: float = 5.0
var locked: bool = false

var original_head_bob_position: Vector3 = Vector3.ZERO
var bob_index: float = 0.0
var bob_vector: Vector3 = Vector3.ZERO
var bob_accumulator: float = 0.0

var base_camera_fov: float = 75.0
var current_camera_fov: float ## Change this variable from the outside to change the fov smoothly in physic_process

var rotation_state: RotationState = RotationState.NoRotation
var rotation_z_axis_progression: float = 0.0:
	set(value):
		rotation_z_axis_progression = clampf(value, 0.0, 1.0)
var target_angle_z: float = 0.0
var return_angle_z: float = 0.0
var rotation_speed_z: float = 4.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and IndieBlueprintInputHelper.is_mouse_captured():
		var motion: InputEventMouseMotion = event.xformed_by(root_node.get_final_transform())
		last_mouse_input += motion.relative
	

func _ready() -> void:
	assert(actor is Node3D, "IndieBlueprintCameraController: the actor Node3D is not set, this camera controller needs a reference to apply the camera movement")
	
	current_horizontal_limit = camera_horizontal_limit
	current_vertical_limit = camera_vertical_limit
	
	mouse_sensitivity = IndieBlueprintSettingsManager.get_accessibility_section(IndieBlueprintGameSettings.MouseSensivitySetting)
	controller_joystick_sensitivity = IndieBlueprintSettingsManager.get_accessibility_section(IndieBlueprintGameSettings.ControllerSensivitySetting)
	
	if camera:
		var accessibility_settings_fov  = IndieBlueprintSettingsManager.get_accessibility_section(IndieBlueprintGameSettings.CameraFovSetting)
		
		if accessibility_settings_fov:
			base_camera_fov = accessibility_settings_fov
		else:
			base_camera_fov = 75.0
		
		camera.fov = base_camera_fov
		current_camera_fov = camera.fov
		
	if bob_head != null:
		original_head_bob_position = bob_head.position
		
	IndieBlueprintSettingsManager.updated_setting_section.connect(on_setting_section_updated)


func _physics_process(delta: float) -> void:
	rotate_camera_with_mouse(last_mouse_input)
	rotate_camera_with_gamepad(delta)
	swing_head(delta)
	headbob(delta)
	fov_adjustment(delta, current_camera_fov)
	rotation_z_axis(delta, target_angle_z, return_angle_z, rotation_speed_z)

## When the target_angle is reached it comes back to the return_angle provided
func rotation_z_axis(delta: float, target_angle: float, return_angle: float, rotation_speed: float) -> void:
	if rotation_state == RotationState.RotationZ:
		rotation_z_axis_progression += delta * rotation_speed;
		camera.rotation.z = lerp_angle(camera.rotation.z, target_angle, rotation_z_axis_progression)
		
		var difference: float = absf(target_angle - camera.rotation.z)
			
		if (difference < 0.01):
			rotation_z_axis_progression = 0
			
			if is_equal_approx(snappedf(camera.rotation.z, 0.01), snappedf(return_angle, 0.01)):
				rotation_state = RotationState.NoRotation
				camera.rotation.z = return_angle
			else:
				if target_angle != return_angle:
					change_rotation_z(return_angle, return_angle, rotation_speed)

## Useful to apply landing hits or damage hits
func change_rotation_z(target_angle: float, return_angle: float = 0.0, rotation_speed: float = 4.0) -> void:
	rotation_state = RotationState.RotationZ
	target_angle_z = target_angle
	return_angle_z = return_angle
	rotation_speed_z = rotation_speed
 

func rotate_camera_with_gamepad(_delta: float) -> void:
	var joystick_motion: Vector2 = actor.motion_input.input_right_motion_as_vector
	
	if joystick_motion.length() >= 0.2:
		var controller_sensitivity: float = controller_joystick_sensitivity / 100 # 5 becomes 0.05
		var twist_input: float = -joystick_motion.x * controller_sensitivity ## Giro
		var pitch_input: float = -joystick_motion.y * controller_sensitivity ## Cabeceo
		
		actor.rotate_y(twist_input)
		camera_pivot.rotate_x(pitch_input)
		
		actor.rotation_degrees.y = limit_horizontal_rotation(actor.rotation_degrees.y)
		camera_pivot.rotation_degrees.x = limit_vertical_rotation(camera_pivot.rotation_degrees.x)

		actor.orthonormalize()
		camera_pivot.orthonormalize()
		
	
func rotate_camera_with_mouse(motion: Vector2) -> void:
	if motion.is_zero_approx():
		return
	
	var mouse_sens: float = mouse_sensitivity / 1000 # radians/pixel, 3 becomes 0.003
	var twist_input: float = -motion.x * mouse_sens ## Giro
	var pitch_input: float = -motion.y * mouse_sens ## Cabeceo

	actor.rotate_y(twist_input)
	camera_pivot.rotate_x(pitch_input)
	
	actor.rotation_degrees.y = limit_horizontal_rotation(actor.rotation_degrees.y)
	camera_pivot.rotation_degrees.x = limit_vertical_rotation(camera_pivot.rotation_degrees.x)

	actor.orthonormalize()
	camera_pivot.orthonormalize()
	
	last_mouse_input = Vector2.ZERO
	

func swing_head(delta: float) -> void:
	if rotation_state == RotationState.NoRotation \
		and swing_head_enabled \
		and actor.is_grounded \
		and not actor.state_machine.locked:
			
		var direction = actor.motion_input.input_direction
		
		if direction in IndieBlueprintVectorHelper.horizontal_directions_v2:
			camera.rotation.z = lerp_angle(camera.rotation.z, -sign(direction.x) * deg_to_rad(swing_rotation_degrees), swing_lerp_factor * delta)
		else:
			camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, swing_lerp_recovery_factor * delta)

	
func headbob(delta: float) -> void:
	if bob_enabled and actor.is_grounded and not actor.state_machine.locked:
		bob_accumulator += delta * actor.velocity.length()
		bob_head.position = Vector3(
			cos(bob_accumulator * bob_frequency / 2.0) * bob_amplitude,
			sin(bob_accumulator * bob_frequency) * bob_amplitude,
			0.0
			)
			
	else:
		bob_head.position = original_head_bob_position


func fov_adjustment(delta: float, new_fov: float) -> void:
	if camera and new_fov != camera.fov:
		var velocity: float = maxf(0.5, actor.velocity.length())
		var target_fov = new_fov + fov_smooth_factor * velocity

		camera.fov = lerp(camera.fov, target_fov, delta * fov_lerp_speed)


func enable_headbob() -> void:
	bob_enabled = true


func disable_headbob() -> void:
	bob_enabled = false
	
	
func enable_swing_head() -> void:
	swing_head_enabled = true


func disable_swing_head() -> void:
	swing_head_enabled = false
	
	
func lock() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	locked = true


func unlock() -> void:
	set_physics_process(true)
	set_process_unhandled_input(true)
	locked = false


func limit_vertical_rotation(angle: float) -> float:
	if current_vertical_limit > 0:
		return clampf(angle, -current_vertical_limit, current_vertical_limit)
	
	return angle


func limit_horizontal_rotation(angle: float) -> float:
	if current_horizontal_limit > 0:
		return clampf(angle, -current_horizontal_limit, current_horizontal_limit)
	
	return angle


#region Camera rotation
func change_horizontal_rotation_limit(new_rotation: int) -> void:
	current_horizontal_limit = new_rotation
	
func change_vertical_rotation_limit(new_rotation: int) -> void:
	current_vertical_limit = new_rotation
	
func return_to_original_horizontal_rotation_limit() -> void:
	current_horizontal_limit = camera_horizontal_limit
	
func return_to_original_vertical_rotation_limit() -> void:
	current_vertical_limit = camera_vertical_limit
#endregion

func on_setting_section_updated(section: String, key: String, value: Variant) -> void:
	match section:
		IndieBlueprintGameSettings.AccessibilitySection:
			match key:
				IndieBlueprintGameSettings.MouseSensivitySetting:
					mouse_sensitivity = value
				IndieBlueprintGameSettings.ControllerSensivitySetting:
					controller_joystick_sensitivity = value
				IndieBlueprintGameSettings.CameraFovSetting:
					current_camera_fov = value
