package main

import "core:fmt"
import "core:math"
import "core:math/rand"

import jph "joltc-odin"
import rl "vendor:raylib"

main_crib :: proc() {

	Sphere :: struct {
		body_id: jph.BodyID,
		radius:  f32,
	}

	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Jolt Odin Samples - Crib")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	camera := rl.Camera3D {
		position   = {5, 5, 5},
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	init_physics()
	defer destroy_physics()

	sphere_mesh := rl.GenMeshSphere(1, 8, 8)
	sphere := rl.LoadModelFromMesh(sphere_mesh)

	num_levels := 5
	bar_length: f32 = 0.9
	bar_thickness: f32 = 0.04
	height: f32 = 0.3
	distance: f32 = 0.5 * bar_length - bar_thickness
	base_radius: f32 = 0.08
	bar_size := [3]f32{bar_length, bar_thickness, bar_thickness}
	bar_pos := [3]f32{0, 2.5, 0}

	bar_mesh := rl.GenMeshCube(bar_length, bar_thickness, bar_thickness)
	bar := rl.LoadModelFromMesh(bar_mesh)
	bars := make([dynamic]jph.BodyID)
	defer delete(bars)

	spheres := make([dynamic]Sphere)
	defer delete(spheres)

	bar_vol := bar_length * bar_thickness * bar_thickness
	tree_vol := 2.0 * 4.0 / 3.0 * math.PI * base_radius * base_radius * base_radius + bar_vol

	radii: [5]f32
	radii[0] = base_radius

	for i in 1 ..< num_levels {
		radius := math.pow(3.0 / 4.0 / math.PI * tree_vol, 1.0 / 3.0)
		radii[i] = radius
		tree_vol = 2.0 * tree_vol + bar_vol
	}

	half_bar_size := bar_size / 2
	bar_shape := jph.BoxShape_Create(&half_bar_size, jph.DEFAULT_CONVEX_RADIUS)

	anchor_pos := [3]f32{bar_pos.x, bar_pos.y + height - 0.5 * bar_thickness, bar_pos.z}
	anchor_shape_settings := jph.EmptyShapeSettings_Create(&{0, 0, 0})
	anchor_shape := jph.EmptyShapeSettings_CreateShape(anchor_shape_settings)
	anchor_settings := jph.BodyCreationSettings_Create3(
		cast(^jph.Shape)anchor_shape,
		&anchor_pos,
		nil,
		.Static,
		OBJECT_LAYER_NON_MOVING,
	)
	defer jph.BodyCreationSettings_Destroy(anchor_settings)

	anchor_body := jph.BodyInterface_CreateBody(physics.body_interface, anchor_settings)
	anchor_id := jph.Body_GetID(anchor_body)
	jph.BodyInterface_AddBody(physics.body_interface, anchor_id, .Activate)

	prev_bar_body: ^jph.Body
	for i in 0 ..< num_levels {
		radius := radii[num_levels - i - 1]

		bar_settings := jph.BodyCreationSettings_Create3(
			cast(^jph.Shape)bar_shape,
			&bar_pos,
			nil,
			.Dynamic,
			OBJECT_LAYER_MOVING,
		)
		defer jph.BodyCreationSettings_Destroy(bar_settings)

		bar_body := jph.BodyInterface_CreateBody(physics.body_interface, bar_settings)
		bar_id := jph.Body_GetID(bar_body)
		jph.BodyInterface_AddBody(physics.body_interface, bar_id, .Activate)

		append(&bars, bar_id)

		p1 := [3]f32{bar_pos.x, bar_pos.y + 0.5 * bar_thickness, bar_pos.z}
		p2 := [3]f32{bar_pos.x, bar_pos.y + height - 0.5 * bar_thickness, bar_pos.z}

		bar_constraint_settings: jph.DistanceConstraintSettings
		jph.DistanceConstraintSettings_Init(&bar_constraint_settings)
		bar_constraint_settings.minDistance = height - bar_thickness
		bar_constraint_settings.maxDistance = (height - bar_thickness) + 0.5
		bar_constraint_settings.point1 = p1
		bar_constraint_settings.point2 = p2

		bar_distance_constraint := jph.DistanceConstraint_Create(
			&bar_constraint_settings,
			bar_body,
			prev_bar_body == nil ? anchor_body : prev_bar_body,
		)

		jph.PhysicsSystem_AddConstraint(
			physics.system,
			cast(^jph.Constraint)bar_distance_constraint,
		)

		sphere_pos := [3]f32{bar_pos.x + distance, bar_pos.y - height, bar_pos.z}
		sphere_shape := jph.SphereShape_Create(radius)

		sphere_settings := jph.BodyCreationSettings_Create3(
			cast(^jph.Shape)sphere_shape,
			&sphere_pos,
			nil,
			.Dynamic,
			OBJECT_LAYER_MOVING,
		)
		defer jph.BodyCreationSettings_Destroy(sphere_settings)

		sphere_body := jph.BodyInterface_CreateBody(physics.body_interface, sphere_settings)
		sphere_id := jph.Body_GetID(sphere_body)
		jph.BodyInterface_AddBody(physics.body_interface, sphere_id, .Activate)

		append(&spheres, Sphere{body_id = sphere_id, radius = radius})

		p1 = [3]f32{sphere_pos.x, sphere_pos.y + 0.5 * radius, sphere_pos.z}
		p2 = [3]f32{sphere_pos.x, sphere_pos.y + height - 0.5 * bar_thickness, sphere_pos.z}

		sphere_constraint_settings: jph.DistanceConstraintSettings
		jph.DistanceConstraintSettings_Init(&sphere_constraint_settings)
		sphere_constraint_settings.minDistance = height - bar_thickness
		sphere_constraint_settings.maxDistance = (height - bar_thickness) + 0.5
		sphere_constraint_settings.point1 = p1
		sphere_constraint_settings.point2 = p2

		sphere_distance_constraint := jph.DistanceConstraint_Create(
			&sphere_constraint_settings,
			sphere_body,
			bar_body,
		)

		jph.PhysicsSystem_AddConstraint(
			physics.system,
			cast(^jph.Constraint)sphere_distance_constraint,
		)

		if i == num_levels - 1 {
			sphere_pos.x -= 2.0 * distance

			sphere_settings := jph.BodyCreationSettings_Create3(
				cast(^jph.Shape)sphere_shape,
				&sphere_pos,
				nil,
				.Dynamic,
				OBJECT_LAYER_MOVING,
			)
			defer jph.BodyCreationSettings_Destroy(sphere_settings)

			sphere_body := jph.BodyInterface_CreateBody(physics.body_interface, sphere_settings)
			sphere_id := jph.Body_GetID(sphere_body)
			jph.BodyInterface_AddBody(physics.body_interface, sphere_id, .Activate)

			append(&spheres, Sphere{body_id = sphere_id, radius = radius})

			p1.x -= 2.0 * distance
			p2.x -= 2.0 * distance

			sphere_constraint_settings: jph.DistanceConstraintSettings
			jph.DistanceConstraintSettings_Init(&sphere_constraint_settings)
			sphere_constraint_settings.minDistance = height - bar_thickness
			sphere_constraint_settings.maxDistance = (height - bar_thickness) + 0.5
			sphere_constraint_settings.point1 = p1
			sphere_constraint_settings.point2 = p2

			sphere_distance_constraint := jph.DistanceConstraint_Create(
				&sphere_constraint_settings,
				sphere_body,
				bar_body,
			)

			jph.PhysicsSystem_AddConstraint(
				physics.system,
				cast(^jph.Constraint)sphere_distance_constraint,
			)

		}

		prev_bar_body = bar_body
		bar_pos.y -= height
		bar_pos.x -= distance
	}

	run_physics()

	for !rl.WindowShouldClose() {
		if rl.IsMouseButtonDown(.RIGHT) {
			rl.UpdateCamera(&camera, .FREE)
		} else if rl.IsKeyPressed(.SPACE) {
			physics.is_paused = !physics.is_paused
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.DARKGRAY)
		rl.BeginMode3D(camera)
		{
			//Draw bars
			for bar_id in bars {
				position: [3]f32
				rotation: quaternion128
				jph.BodyInterface_GetPosition(physics.body_interface, bar_id, &position)
				jph.BodyInterface_GetRotation(physics.body_interface, bar_id, &rotation)

				bar.transform = rl.QuaternionToMatrix(rotation)

				rl.DrawModelWires(bar, position, 1, rl.RED)
			}

			//Draw spheres
			for s in spheres {
				position: [3]f32
				rotation: quaternion128
				jph.BodyInterface_GetPosition(physics.body_interface, s.body_id, &position)
				jph.BodyInterface_GetRotation(physics.body_interface, s.body_id, &rotation)

				sphere.transform = rl.QuaternionToMatrix(rotation)

				rl.DrawModelWires(sphere, position, s.radius, rl.RED)
			}

			rl.DrawGrid(10, 1)
			draw_physics_debug()
		}
		rl.EndMode3D()

		rl.DrawFPS(2, 2)
		rl.DrawText(fmt.ctprintf("%2d UPS", physics.ups), 2, 22, 20, rl.GREEN)
	}
}
