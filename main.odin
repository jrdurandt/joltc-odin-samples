package main

import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

import jph "joltc-odin"
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

	demo := "vehicle"
	if len(os.args) >= 1 {
		log.warnf("No demo specified. Defaulting to ballpit")
	} else {
		demo = os.args[1]
	}
	demo = strings.to_lower(demo)
	log.infof("Loading demo: %s", demo)

	if strings.compare(demo, "ballpit") == 0 {
		main_ballpit()
	} else if strings.compare(demo, "crib") == 0 {
		main_crib()
	} else if strings.compare(demo, "terrain") == 0 {
		main_heightmap()
	} else if strings.compare(demo, "vehicle") == 0 {
		main_vehicle()
	} else {
		log.panicf("Invalid demo specific: %s", demo)
	}
}

hex_to_color :: proc "contextless" (rgba: u32) -> rl.Color {
	return rl.Color {
		u8((rgba >> 24) & 0xFF),
		u8((rgba >> 16) & 0xFF),
		u8((rgba >> 8) & 0xFF),
		u8(rgba & 0xFF),
	}
}
