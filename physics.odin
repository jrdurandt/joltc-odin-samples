package main

import "core:log"
import "core:thread"
import "core:time"
import "core:math"

import jph "jolt-odin-latest"

PHYSICS_UPDATED_PER_SECOND :: 1.0 / 60.0
PHYSICS_COLLISION_SUB_STEPS :: 1

OBJECT_LAYER_NON_MOVING: jph.ObjectLayer = 0
OBJECT_LAYER_MOVING: jph.ObjectLayer = 1
OBJECT_LAYER_NUM :: 2

BROAD_PHASE_LAYER_NON_MOVING: jph.BroadPhaseLayer = 0
BROAD_PHASE_LAYER_MOVING: jph.BroadPhaseLayer = 1
BROAD_PHASE_LAYER_NUM :: 2

Physics :: struct {
    job_system: ^jph.JobSystem,
    system: ^jph.PhysicsSystem,
    body_interface: ^jph.BodyInterface,
    is_running: bool,
    ups: int
}

physics: ^Physics

init_physics :: proc(){
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
}

destroy_physics :: proc(){
    physics.is_running = false
    jph.PhysicsSystem_Destroy(physics.system)
    jph.JobSystem_Destroy(physics.job_system)
    free(physics)
    jph.Shutdown()
}

run_physics :: proc(){
    physics.is_running = true
    thread.create_and_start(physics_thread, self_cleanup = true)
}

@(private)
physics_thread :: proc(){
    ups_buff: [30]f32
    last_time := time.now()
    cnt: int

    for physics.is_running {
        now_time := time.now() 
        delta_time := f32(time.duration_seconds(time.diff(last_time, now_time)))

        if delta_time > PHYSICS_UPDATED_PER_SECOND {
            err := jph.PhysicsSystem_Update(
                physics.system,
                delta_time,
                PHYSICS_COLLISION_SUB_STEPS,
                physics.job_system
            ) 

            if err != .None {
                physics.is_running = false
                log.errorf("Error updating physics system: %v", err)
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