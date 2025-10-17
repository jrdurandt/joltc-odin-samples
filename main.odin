package main

import "core:log"
import "core:mem"

import jph "jolt-odin"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

main :: proc() {
	context.logger = log.create_console_logger(.Info)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		context.logger.lowest_level = .Debug
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer {
			if len(track.allocation_map) > 0 {
				log.errorf("=== %v allocation not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					log.errorf("- %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				log.errorf("=== %v incorrect frees: ===", len(track.bad_free_array))
				for entry in track.bad_free_array {
					log.errorf("- %p @ %v", entry.memory, entry.location)
				}
			}
		}
	}

	log.debug("DEBUG ENABLED")

	// main_ballpit()
	main_crib()
}

hex_to_color :: proc "contextless" (rgba: u32) -> rl.Color {
	return rl.Color {
		u8((rgba >> 24) & 0xFF),
		u8((rgba >> 16) & 0xFF),
		u8((rgba >> 8) & 0xFF),
		u8(rgba & 0xFF),
	}
}
