package obj_viewer
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:log"
import "base:runtime"
import "core:time"
import rd "../Redef/src"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4,4]f32

to_radians :: math.to_radians_f32
round      :: math.round_f32
pow        :: linalg.pow
max        :: math.max
min        :: math.min

MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE,
}

g := struct {
    player:      Player,
    camera:      Camera,
    renderer:    Renderer,
    selected:    EntityID,
    lmb_click:   bool,
    frame:       uint,
    dt,
    fov:         f32,
    fullscreen,
    running: bool

} {
    fov = 90,
    running = true
}


Mode :: enum {
    PLAY,
    EDIT,
}

TRANSFORM_IDENTITY :: Transform {
    translation = 0,
    scale = 1,
    rotation = 0
}

KeyEvent :: rd.KeyboardEvent

KeyboardEvents :: [dynamic; 64]KeyEvent

DebugInfo :: struct {
    frame_time:         time.Duration,
    draw_call_count:    u32,
    player_speed:       f32,
    fps:                u32,
}


Scene :: struct {
    assets:       [dynamic]Asset,
    entities: #soa[dynamic]Entity,
}

in_bounds :: proc(p: vec2, rect: Rect) -> bool {
    return p.x >= rect.x && p.x < rect.x + rect.w && p.y >= rect.y && p.y < rect.y + rect.h
}

to_vec4 :: proc(v: vec3, f: f32) -> vec4 { return vec4{v.x, v.y, v.z, f} }

norm :: proc(v: vec3) -> f32 { return math.sqrt_f32(v.x*v.x + v.y*v.y + v.z*v.z) }

random_range :: proc(min: f32, max: f32) -> f32 {
    return rand.float32() * (max - min) + min
}