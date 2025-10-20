package main

import "core:fmt"
import "core:math"
import "core:math/noise"
import "core:math/rand"
import jph "jolt-odin"
import rl "vendor:raylib"

main_heightmap :: proc() {
	seed: i64 = 42069
	n := 128
	s: f32 = 5

	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Jolt Odin Samples - Terrain")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	camera := rl.Camera3D {
		position   = {5, 50, 5},
		target     = {f32(n), 0, f32(n)},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	heightmap_data := make([]f32, n * n)
	defer delete(heightmap_data)

	for y in 0 ..< n {
		for x in 0 ..< n {
			height := noise.noise_2d(seed, {f64(x) * 8.0 / f64(n), f64(y) * 8.0 / f64(n)})
			heightmap_data[y * n + x] = math.remap(height, -1, 1, 0, 1)
		}
	}

	heightmap_pixels := make([]u8, len(heightmap_data) * 4)
	defer delete(heightmap_pixels)

	p := 0
	for height in heightmap_data {
		pixel := u8(height * 255)
		heightmap_pixels[p] = pixel
		heightmap_pixels[p + 1] = pixel
		heightmap_pixels[p + 2] = pixel
		heightmap_pixels[p + 3] = 255
		p += 4
	}

	heightmap_img: rl.Image = {
		data    = raw_data(heightmap_pixels),
		width   = i32(n),
		height  = i32(n),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}

	heightmap_tex := rl.LoadTextureFromImage(heightmap_img)
	defer rl.UnloadTexture(heightmap_tex)

	heightmap_mesh := rl.GenMeshHeightmap(heightmap_img, {f32(n), s, f32(n)})
	heightmap_model := rl.LoadModelFromMesh(heightmap_mesh)
	defer rl.UnloadModel(heightmap_model)
	heightmap_model.materials[0].maps[0].texture = heightmap_tex

	sphere_mesh := rl.GenMeshSphere(0.2, 8, 8)
	sphere := rl.LoadModelFromMesh(sphere_mesh)

	init_physics()
	defer destroy_physics()

	height_field_settings := jph.HeightFieldShapeSettings_Create(
		raw_data(heightmap_data),
		&{0, 0, 0},
		&{1, s, 1},
		u32(n),
		nil,
	)

	height_field_shape := jph.HeightFieldShapeSettings_CreateShape(height_field_settings)
	defer jph.Shape_Destroy(cast(^jph.Shape)height_field_shape)

	terrain_settings := jph.BodyCreationSettings_Create3(
		cast(^jph.Shape)height_field_shape,
		&{0, 0, 0},
		nil,
		.Static,
		OBJECT_LAYER_NON_MOVING,
	)
	defer jph.BodyCreationSettings_Destroy(terrain_settings)

	jph.BodyCreationSettings_SetRestitution(terrain_settings, 0.5)
	jph.BodyCreationSettings_SetFriction(terrain_settings, 0.5)

	terrain_id := jph.BodyInterface_CreateAndAddBody(
		physics.body_interface,
		terrain_settings,
		.DontActivate,
	)
	defer jph.BodyInterface_RemoveAndDestroyBody(physics.body_interface, terrain_id)

	drops: [dynamic]jph.BodyID
	defer {
		for drop_id in drops {
			jph.BodyInterface_RemoveAndDestroyBody(physics.body_interface, drop_id)
		}
		delete(drops)
	}

	sphere_shape := jph.SphereShape_Create(0.2)
	jph.PhysicsSystem_OptimizeBroadPhase(physics.system)

	removed_drops: [dynamic]int
	defer delete(removed_drops)

	run_physics()

	is_spawning: bool = false
	for !rl.WindowShouldClose() {
		if rl.IsMouseButtonDown(.RIGHT) {
			rl.UpdateCamera(&camera, .FREE)
		} else if rl.IsKeyPressed(.SPACE) {
			is_spawning = !is_spawning
		}

		if is_spawning {
			drop_pos := [3]f32 {
				rand.float32_range(0, f32(n)),
				rand.float32_range(30, 50),
				rand.float32_range(0, f32(n)),
			}

			sphere_settings := jph.BodyCreationSettings_Create3(
				cast(^jph.Shape)sphere_shape,
				&drop_pos,
				nil,
				.Dynamic,
				OBJECT_LAYER_MOVING,
			)
			defer jph.BodyCreationSettings_Destroy(sphere_settings)

			drop_id := jph.BodyInterface_CreateAndAddBody(
				physics.body_interface,
				sphere_settings,
				.Activate,
			)

			append(&drops, drop_id)
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)
		{
			rl.DrawModelWires(heightmap_model, {0, 0, 0}, 1, rl.GREEN)

			//Draw drops
			drop_loop: for drop_id, drop_index in drops {
				position: [3]f32
				rotation: quaternion128

				jph.BodyInterface_GetPosition(physics.body_interface, drop_id, &position)
				jph.BodyInterface_GetRotation(physics.body_interface, drop_id, &rotation)

				//Kill plane
				if position.y <= -50 {
					append(&removed_drops, drop_index)
					continue drop_loop
				}

				sphere.transform = rl.QuaternionToMatrix(rotation)

				is_active := jph.BodyInterface_IsActive(physics.body_interface, drop_id)
				rl.DrawModel(sphere, position, 1, is_active ? rl.BLUE : rl.GRAY)
				rl.DrawModelWires(sphere, position, 1, rl.DARKGRAY)
			}

			for drop_index in removed_drops {
				drop_id := drops[drop_index]
				jph.BodyInterface_RemoveAndDestroyBody(physics.body_interface, drop_id)
				unordered_remove(&drops, drop_index)
			}
			clear(&removed_drops)

			draw_physics_debug()
		}
		rl.EndMode3D()

		// rl.DrawTexture(heightmap_tex, 0, 0, rl.WHITE)
		rl.DrawFPS(2, 2)
		rl.DrawText(fmt.ctprintf("%2d UPS", physics.ups), 2, 22, 20, rl.GREEN)

		rl.DrawText(
			fmt.ctprintf(
				"Hold RIGHT mouse button and use WASD for camera control.\nLEFT click to select drops.\nPress space to %v spawning drops.\nDrops: %d",
				is_spawning ? "stop" : "start",
				len(drops),
			),
			2,
			42,
			20,
			rl.WHITE,
		)
	}
}
