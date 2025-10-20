package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:thread"
import "core:time"

import jph "jolt-odin"
import rl "vendor:raylib"

PHYSICS_UPDATED_PER_SECOND :: 1.0 / 60.0
PHYSICS_COLLISION_SUB_STEPS :: 1

OBJECT_LAYER_NON_MOVING: jph.ObjectLayer = 0
OBJECT_LAYER_MOVING: jph.ObjectLayer = 1
OBJECT_LAYER_NUM :: 2

BROAD_PHASE_LAYER_NON_MOVING: jph.BroadPhaseLayer = 0
BROAD_PHASE_LAYER_MOVING: jph.BroadPhaseLayer = 1
BROAD_PHASE_LAYER_NUM :: 2

Physics :: struct {
	job_system:          ^jph.JobSystem,
	system:              ^jph.PhysicsSystem,
	body_interface:      ^jph.BodyInterface,
	is_running:          bool,
	is_paused:           bool,
	ups:                 int,
	debug_renderer_proc: ^jph.DebugRenderer_Procs,
	debug_renderer:      ^jph.DebugRenderer,
	debug_draw_settings: jph.DrawSettings,
}

physics: ^Physics

init_physics :: proc() {
	assert(jph.Init(), "Failed to init Jolt Physics")

	physics = new(Physics)

	physics.job_system = jph.JobSystemThreadPool_Create(nil)
	assert(physics.job_system != nil, "Failed to create physics job system")

	object_layer_pair_filter := jph.ObjectLayerPairFilterTable_Create(OBJECT_LAYER_NUM)
	jph.ObjectLayerPairFilterTable_EnableCollision(
		object_layer_pair_filter,
		OBJECT_LAYER_MOVING,
		OBJECT_LAYER_MOVING,
	)
	jph.ObjectLayerPairFilterTable_EnableCollision(
		object_layer_pair_filter,
		OBJECT_LAYER_MOVING,
		OBJECT_LAYER_NON_MOVING,
	)

	broad_phase_layer_interface_table := jph.BroadPhaseLayerInterfaceTable_Create(
		OBJECT_LAYER_NUM,
		BROAD_PHASE_LAYER_NUM,
	)
	jph.BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
		broad_phase_layer_interface_table,
		OBJECT_LAYER_NON_MOVING,
		BROAD_PHASE_LAYER_NON_MOVING,
	)
	jph.BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
		broad_phase_layer_interface_table,
		OBJECT_LAYER_MOVING,
		BROAD_PHASE_LAYER_MOVING,
	)

	object_vs_broad_phase_layer_filter := jph.ObjectVsBroadPhaseLayerFilterTable_Create(
		broad_phase_layer_interface_table,
		BROAD_PHASE_LAYER_NUM,
		object_layer_pair_filter,
		OBJECT_LAYER_NUM,
	)

	physics_system_settings := jph.PhysicsSystemSettings {
		maxBodies                     = 65535,
		numBodyMutexes                = 0,
		maxBodyPairs                  = 65535,
		maxContactConstraints         = 65535,
		broadPhaseLayerInterface      = broad_phase_layer_interface_table,
		objectLayerPairFilter         = object_layer_pair_filter,
		objectVsBroadPhaseLayerFilter = object_vs_broad_phase_layer_filter,
	}

	physics.system = jph.PhysicsSystem_Create(&physics_system_settings)
	assert(physics.system != nil, "Failed to create Jolt physics system")

	physics.body_interface = jph.PhysicsSystem_GetBodyInterface(physics.system)

	physics.debug_renderer = jph.DebugRenderer_Create(nil)

	physics.debug_renderer_proc = new(jph.DebugRenderer_Procs)
	physics.debug_renderer_proc.DrawLine = debug_renderer_draw_line
	physics.debug_renderer_proc.DrawTriangle = debug_renderer_draw_triangle
	physics.debug_renderer_proc.DrawText3D = debug_renderer_draw_text_3D
	jph.DebugRenderer_SetProcs(physics.debug_renderer_proc)

	jph.DrawSettings_InitDefault(&physics.debug_draw_settings)
	// physics.debug_draw_settings.drawBoundingBox = true
	physics.debug_draw_settings.drawShape = false
	// physics.debug_draw_settings.drawShapeWireframe = true
	// physics.debug_draw_settings.drawVelocity = true
	// physics.debug_draw_settings.drawMassAndInertia = true
}

destroy_physics :: proc() {
	physics.is_running = false
	free(physics.debug_renderer_proc)
	jph.DebugRenderer_Destroy(physics.debug_renderer)
	jph.PhysicsSystem_Destroy(physics.system)
	jph.JobSystem_Destroy(physics.job_system)
	free(physics)
	jph.Shutdown()
}

run_physics :: proc() {
	physics.is_running = true
	thread.create_and_start(physics_thread, self_cleanup = true)
}

draw_physics_debug :: proc() {
	jph.PhysicsSystem_DrawBodies(
		physics.system,
		&physics.debug_draw_settings,
		physics.debug_renderer,
		nil,
	)

	jph.PhysicsSystem_DrawConstraints(physics.system, physics.debug_renderer)
	jph.PhysicsSystem_DrawConstraintLimits(physics.system, physics.debug_renderer)
}

@(private)
physics_thread :: proc() {
	ups_buff: [30]f32
	last_time := time.now()
	cnt: int

	for physics.is_running {
		now_time := time.now()
		delta_time := f32(time.duration_seconds(time.diff(last_time, now_time)))

		if delta_time > PHYSICS_UPDATED_PER_SECOND {
			if !physics.is_paused {
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
			}

			i := cnt % 30
			ups_buff[i] = delta_time

			delta_accum: f32 = 0
			for dt in ups_buff {
				delta_accum += dt
			}
			avg_ups := delta_accum / 30
			physics.ups = int(math.ceil(1.0 / avg_ups))

			last_time = now_time
			cnt += 1
		}
	}
}

debug_renderer_draw_line :: proc "c" (
	user_ptr: rawptr,
	start_pos: ^jph.RVec3,
	end_pos: ^jph.RVec3,
	color: jph.Color,
) {
	col := hex_to_color(color)
	rl.DrawLine3D(start_pos^, end_pos^, col)
}


debug_renderer_draw_triangle :: proc "c" (
	user_ptr: rawptr,
	point_0: ^jph.RVec3,
	point_1: ^jph.RVec3,
	point_2: ^jph.RVec3,
	color: jph.Color,
	cast_shadow: jph.DebugRenderer_CastShadow,
) {
	col := hex_to_color(color)
	rl.DrawLine3D(point_0^, point_1^, col)
	rl.DrawLine3D(point_1^, point_2^, col)
	rl.DrawLine3D(point_2^, point_0^, col)
}

debug_renderer_draw_text_3D :: proc "c" (
	user_ptr: rawptr,
	world_pos: ^jph.RVec3,
	text: cstring,
	color: jph.Color,
	size: f32,
) {

}
