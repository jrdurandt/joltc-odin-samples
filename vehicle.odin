package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/noise"
import "core:math/rand"
import "core:testing"
import jph "jolt-odin"
import rl "vendor:raylib"

main_vehicle :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Jolt Odin Samples - Vehicle")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	camera := rl.Camera3D {
		position   = {5, 5, 5},
		target     = {0, 2, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	init_physics()
	defer destroy_physics()

	floor_shape := jph.BoxShape_Create(&{1000, 1.0, 1000}, jph.DEFAULT_CONVEX_RADIUS)
	floor_settings := jph.BodyCreationSettings_Create3(
		cast(^jph.Shape)floor_shape,
		&{0, -1, 0},
		nil,
		.Static,
		OBJECT_LAYER_NON_MOVING,
	)
	jph.BodyCreationSettings_SetFriction(floor_settings, 1.0)
	jph.BodyInterface_CreateAndAddBody(physics.body_interface, floor_settings, .DontActivate)

	position := [3]f32{0, 2, 0}
	initial_roll_angle: f32 = 0
	max_roll_angle: f32 = math.to_radians_f32(60)
	max_steering_angle: f32 = math.to_radians_f32(30)

	front_suspension_sideways_angle: f32 = 0
	front_suspension_forward_angle: f32 = 0
	front_king_pin_angle: f32 = 0
	front_caster_angle: f32 = 0
	front_camber: f32 = 0
	front_toe: f32 = 0
	front_suspension_min_length: f32 = 0.3
	front_suspension_max_length: f32 = 0.5
	front_suspension_frequency: f32 = 1.5
	front_suspension_damping: f32 = 0.5

	rear_suspension_sideways_angle: f32 = 0
	rear_suspension_forward_angle: f32 = 0
	rear_king_pin_angle: f32 = 0
	rear_caster_angle: f32 = 0
	rear_camber: f32 = 0
	rear_toe: f32 = 0
	rear_suspension_min_length: f32 = 0.3
	rear_suspension_max_length: f32 = 0.5
	rear_suspension_frequency: f32 = 1.5
	rear_suspension_damping: f32 = 0.5

	wheel_radius: f32 = 0.3
	wheel_width: f32 = 0.1
	half_vehicle_size := [3]f32{0.9, 0.2, 2.0}

	car_mesh := rl.GenMeshCube(
		half_vehicle_size.x * 2,
		half_vehicle_size.y * 2,
		half_vehicle_size.z * 2,
	)
	car_model := rl.LoadModelFromMesh(car_mesh)
	defer rl.UnloadModel(car_model)

	wheel_mesh := rl.GenMeshCylinder(wheel_radius, wheel_width, 8)
	wheel_model := rl.LoadModelFromMesh(wheel_mesh)
	defer rl.UnloadModel(wheel_model)

	testers: [3]^jph.VehicleCollisionTester
	testers[0] = cast(^jph.VehicleCollisionTester)jph.VehicleCollisionTesterRay_Create(
		OBJECT_LAYER_NON_MOVING,
		&{0, 1, 0},
		math.PI / 4,
	)
	testers[1] = cast(^jph.VehicleCollisionTester)jph.VehicleCollisionTesterCastSphere_Create(
		OBJECT_LAYER_NON_MOVING,
		0.5 * wheel_radius,
		&{0, 1, 0},
		math.to_radians_f32(80),
	)
	testers[2] = cast(^jph.VehicleCollisionTester)jph.VehicleCollisionTesterCastCylinder_Create(
		OBJECT_LAYER_NON_MOVING,
		jph.DEFAULT_COLLISION_TOLERANCE,
	)

	// Create vehicle body
	body_box_shape := jph.BoxShape_Create(&half_vehicle_size, jph.DEFAULT_CONVEX_RADIUS)
	car_shape := jph.OffsetCenterOfMassShape_Create(
		&{0, -half_vehicle_size.y, 0},
		cast(^jph.Shape)body_box_shape,
	)

	rot := linalg.quaternion_from_euler_angle_z(initial_roll_angle)
	car_body_settings := jph.BodyCreationSettings_Create3(
		cast(^jph.Shape)car_shape,
		&position,
		&rot,
		.Dynamic,
		OBJECT_LAYER_MOVING,
	)

	jph.BodyCreationSettings_SetOverrideMassProperties(
		cast(^jph.BodyCreationSettings)car_body_settings,
		.CalculateInertia,
	)
	mass_property_override := jph.MassProperties {
		mass = 1500,
	}
	jph.BodyCreationSettings_SetMassPropertiesOverride(
		cast(^jph.BodyCreationSettings)car_body_settings,
		&mass_property_override,
	)
	car_body := jph.BodyInterface_CreateBody(
		physics.body_interface,
		cast(^jph.BodyCreationSettings)car_body_settings,
	)
	car_body_id := jph.Body_GetID(car_body)
	jph.BodyInterface_AddBody(physics.body_interface, car_body_id, .Activate)

	// Create vehicle constraint
	vehicle: jph.VehicleConstraintSettings
	// jph.VehicleConstraintSettings_Init(&vehicle)
	vehicle.base.drawConstraintSize = 0.1
	vehicle.maxPitchRollAngle = max_roll_angle

	vehicle.up = {0, 1, 0}
	vehicle.forward = {0, 0, 1}

	// Suspension direction
	front_suspension_dir := linalg.normalize(
		[3]f32 {
			math.tan(front_suspension_sideways_angle),
			-1,
			math.tan(front_suspension_forward_angle),
		},
	)
	front_steering_axis := linalg.normalize(
		[3]f32{-math.tan(front_king_pin_angle), 1, -math.tan(front_caster_angle)},
	)
	front_wheel_up := [3]f32{math.sin(front_camber), math.cos(front_camber), 0}
	front_wheel_forward := [3]f32{-math.sin(front_toe), 0, math.cos(front_toe)}

	rear_suspension_dir := linalg.normalize(
		[3]f32 {
			math.tan(rear_suspension_sideways_angle),
			-1,
			math.tan(rear_suspension_forward_angle),
		},
	)
	rear_steering_axis := linalg.normalize(
		[3]f32{-math.tan(rear_king_pin_angle), 1, -math.tan(rear_caster_angle)},
	)
	rear_wheel_up := [3]f32{math.sin(rear_camber), math.cos(rear_camber), 0}
	rear_wheel_forward := [3]f32{-math.sin(rear_toe), 0, math.cos(rear_toe)}
	flip_x := [3]f32{-1, 1, 1}

	// Wheels, left front
	front_spring_settings := jph.SpringSettings {
		mode                 = .FrequencyAndDamping,
		damping              = front_suspension_damping,
		frequencyOrStiffness = front_suspension_frequency,
	}

	w1 := jph.WheelSettingsWV_Create()
	wheel_pos := [3]f32 {
		half_vehicle_size.x,
		-0.9 * half_vehicle_size.y,
		half_vehicle_size.z - 2.0 * wheel_radius,
	}
	jph.WheelSettings_SetPosition(cast(^jph.WheelSettings)w1, &wheel_pos)
	jph.WheelSettings_SetSuspensionForcePoint(cast(^jph.WheelSettings)w1, &wheel_pos)
	jph.WheelSettings_SetEnableSuspensionForcePoint(cast(^jph.WheelSettings)w1, true)
	jph.WheelSettings_SetSuspensionDirection(cast(^jph.WheelSettings)w1, &front_suspension_dir)
	jph.WheelSettings_SetSteeringAxis(cast(^jph.WheelSettings)w1, &front_steering_axis)
	jph.WheelSettings_SetWheelUp(cast(^jph.WheelSettings)w1, &front_wheel_up)
	jph.WheelSettings_SetWheelForward(cast(^jph.WheelSettings)w1, &front_wheel_forward)
	jph.WheelSettings_SetSuspensionMinLength(
		cast(^jph.WheelSettings)w1,
		front_suspension_min_length,
	)
	jph.WheelSettings_SetSuspensionMaxLength(
		cast(^jph.WheelSettings)w1,
		front_suspension_max_length,
	)
	jph.WheelSettings_SetSuspensionSpring(cast(^jph.WheelSettings)w1, &front_spring_settings)
	jph.WheelSettingsWV_SetMaxSteerAngle(w1, max_steering_angle)
	jph.WheelSettingsWV_SetMaxHandBrakeTorque(w1, 0)

	// Right front
	w2 := jph.WheelSettingsWV_Create()
	wheel_pos = [3]f32 {
		-half_vehicle_size.x,
		-0.9 * half_vehicle_size.y,
		half_vehicle_size.z - 2.0 * wheel_radius,
	}
	jph.WheelSettings_SetPosition(cast(^jph.WheelSettings)w2, &wheel_pos)
	jph.WheelSettings_SetSuspensionForcePoint(cast(^jph.WheelSettings)w2, &wheel_pos)
	jph.WheelSettings_SetEnableSuspensionForcePoint(cast(^jph.WheelSettings)w2, true)

	// front_suspension_dir *= flip_x
	jph.WheelSettings_SetSuspensionDirection(cast(^jph.WheelSettings)w2, &front_suspension_dir)
	// front_steering_axis *= flip_x
	jph.WheelSettings_SetSteeringAxis(cast(^jph.WheelSettings)w2, &front_steering_axis)
	// front_wheel_up *= flip_x
	jph.WheelSettings_SetWheelUp(cast(^jph.WheelSettings)w2, &front_wheel_up)
	// front_wheel_forward *= flip_x
	jph.WheelSettings_SetWheelForward(cast(^jph.WheelSettings)w2, &front_wheel_forward)
	jph.WheelSettings_SetSuspensionMinLength(
		cast(^jph.WheelSettings)w2,
		front_suspension_min_length,
	)
	jph.WheelSettings_SetSuspensionMaxLength(
		cast(^jph.WheelSettings)w2,
		front_suspension_max_length,
	)
	jph.WheelSettings_SetSuspensionSpring(cast(^jph.WheelSettings)w2, &front_spring_settings)
	jph.WheelSettingsWV_SetMaxSteerAngle(w2, max_steering_angle)
	jph.WheelSettingsWV_SetMaxHandBrakeTorque(w2, 0)

	// Left Rear
	rear_spring_settings := jph.SpringSettings {
		mode                 = .FrequencyAndDamping,
		damping              = rear_suspension_damping,
		frequencyOrStiffness = rear_suspension_frequency,
	}

	w3 := jph.WheelSettingsWV_Create()
	wheel_pos = [3]f32 {
		half_vehicle_size.x,
		-0.9 * half_vehicle_size.y,
		-half_vehicle_size.z + 2.0 * wheel_radius,
	}
	jph.WheelSettings_SetPosition(cast(^jph.WheelSettings)w3, &wheel_pos)
	jph.WheelSettings_SetSuspensionForcePoint(cast(^jph.WheelSettings)w3, &wheel_pos)
	jph.WheelSettings_SetEnableSuspensionForcePoint(cast(^jph.WheelSettings)w3, true)
	jph.WheelSettings_SetSuspensionDirection(cast(^jph.WheelSettings)w3, &rear_suspension_dir)
	jph.WheelSettings_SetSteeringAxis(cast(^jph.WheelSettings)w3, &rear_steering_axis)
	jph.WheelSettings_SetWheelUp(cast(^jph.WheelSettings)w3, &rear_wheel_up)
	jph.WheelSettings_SetWheelForward(cast(^jph.WheelSettings)w3, &rear_wheel_forward)
	jph.WheelSettings_SetSuspensionMinLength(
		cast(^jph.WheelSettings)w3,
		rear_suspension_min_length,
	)
	jph.WheelSettings_SetSuspensionMaxLength(
		cast(^jph.WheelSettings)w3,
		rear_suspension_max_length,
	)
	jph.WheelSettings_SetSuspensionSpring(cast(^jph.WheelSettings)w3, &rear_spring_settings)
	jph.WheelSettingsWV_SetMaxSteerAngle(w3, 0)

	// Right rear
	w4 := jph.WheelSettingsWV_Create()
	wheel_pos = [3]f32 {
		-half_vehicle_size.x,
		-0.9 * half_vehicle_size.y,
		-half_vehicle_size.z + 2.0 * wheel_radius,
	}
	jph.WheelSettings_SetPosition(cast(^jph.WheelSettings)w4, &wheel_pos)
	jph.WheelSettings_SetSuspensionForcePoint(cast(^jph.WheelSettings)w4, &wheel_pos)
	jph.WheelSettings_SetEnableSuspensionForcePoint(cast(^jph.WheelSettings)w4, true)

	// rear_suspension_dir *= flip_x
	jph.WheelSettings_SetSuspensionDirection(cast(^jph.WheelSettings)w4, &rear_suspension_dir)
	// rear_steering_axis *= flip_x
	jph.WheelSettings_SetSteeringAxis(cast(^jph.WheelSettings)w4, &rear_steering_axis)
	// rear_wheel_up *= flip_x
	jph.WheelSettings_SetWheelUp(cast(^jph.WheelSettings)w4, &rear_wheel_up)
	// rear_wheel_forward *= flip_x
	jph.WheelSettings_SetWheelForward(cast(^jph.WheelSettings)w4, &rear_wheel_forward)
	jph.WheelSettings_SetSuspensionMinLength(
		cast(^jph.WheelSettings)w4,
		rear_suspension_min_length,
	)
	jph.WheelSettings_SetSuspensionMaxLength(
		cast(^jph.WheelSettings)w4,
		rear_suspension_max_length,
	)
	jph.WheelSettings_SetSuspensionSpring(cast(^jph.WheelSettings)w4, &rear_spring_settings)
	jph.WheelSettingsWV_SetMaxSteerAngle(w4, 0)

	wheels: [4]^jph.WheelSettings

	wheels[0] = cast(^jph.WheelSettings)w1
	wheels[1] = cast(^jph.WheelSettings)w2
	wheels[2] = cast(^jph.WheelSettings)w3
	wheels[3] = cast(^jph.WheelSettings)w4

	for w in wheels {
		jph.WheelSettings_SetRadius(w, wheel_radius)
		jph.WheelSettings_SetWidth(w, wheel_width)
	}

	vehicle.wheels = &wheels[0]
	vehicle.wheelsCount = 4

	controller := jph.WheeledVehicleControllerSettings_Create()
	vehicle.controller = cast(^jph.VehicleControllerSettings)controller

	// engine: jph.VehicleEngineSettings
	// jph.VehicleEngineSettings_Init(&engine)
	// engine.maxTorque = max_engine_torque
	// jph.WheeledVehicleControllerSettings_SetEngine(controller, &engine)

	// transmission := jph.VehicleTransmissionSettings_Create()
	// jph.VehicleTransmissionSettings_SetClutchStrength(transmission, clutch_strength)
	// jph.WheeledVehicleControllerSettings_SetTransmission(controller, transmission)

	// Differential
	differentials: [1]jph.VehicleDifferentialSettings
	differentials[0].leftWheel = 2
	differentials[0].rightWheel = 3
	jph.WheeledVehicleControllerSettings_SetDifferentials(controller, &differentials[0], 1)

	vehicle_constraint := jph.VehicleConstraint_Create(car_body, &vehicle)

	jph.PhysicsSystem_AddConstraint(physics.system, cast(^jph.Constraint)vehicle_constraint)
	jph.PhysicsSystem_AddStepListener(
		physics.system,
		cast(^jph.PhysicsStepListener)vehicle_constraint,
	)

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		right: f32 = 0.0
		if rl.IsMouseButtonDown(.RIGHT) {
			rl.UpdateCamera(&camera, .FREE)
		} else {
			if rl.IsKeyDown(.RIGHT) {
				right = 1
			} else if rl.IsKeyDown(.LEFT) {
				right = -1
			}
		}

		controller := cast(^jph.WheeledVehicleController)jph.VehicleConstraint_GetController(
			vehicle_constraint,
		)

		jph.WheeledVehicleController_SetDriverInput(controller, 0, right, 0, 0)
		jph.VehicleConstraint_SetVehicleCollisionTester(vehicle_constraint, testers[0])

		err := jph.PhysicsSystem_Update(
			physics.system,
			delta_time,
			PHYSICS_COLLISION_SUB_STEPS,
			physics.job_system,
		)

		if err != .None {
			physics.is_running = false
			log.errorf("Error updating physics system: %v", err)
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)
		{
			rl.DrawGrid(10, 1)
			rl.DrawPlane({0, -0.01, 0}, {10, 10}, rl.DARKGREEN)

			car_position: [3]f32
			car_rotation: quaternion128

			jph.BodyInterface_GetPosition(physics.body_interface, car_body_id, &car_position)
			jph.BodyInterface_GetRotation(physics.body_interface, car_body_id, &car_rotation)

			car_model.transform = rl.QuaternionToMatrix(car_rotation)

			rl.DrawModel(car_model, car_position, 1, rl.RED)

			for w in 0 ..< len(wheels) {
				wheel_transform: jph.Mat4
				jph.VehicleConstraint_GetWheelWorldTransform(
					vehicle_constraint,
					u32(w),
					&{0, 1, 0},
					&{1, 0, 0},
					&wheel_transform,
				)

				wheel_model.transform = rl.MatrixTranspose(transmute(rl.Matrix)wheel_transform)
				rl.DrawModelWires(wheel_model, {0, 0, 0}, 1, rl.YELLOW)

			}

			draw_physics_debug()
		}
		rl.EndMode3D()

		rl.DrawFPS(2, 2)
	}
}
