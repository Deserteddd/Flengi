package obj_viewer


import fp "core:path/filepath"
import rd "../Redef/src"
import gl "vendor:cgltf"
import stbi "vendor:stb/image"
import "core:log"
import "core:strings"
import "core:mem"
import "core:slice"
import "core:os"
import "core:path/filepath"

Asset :: struct {
    name,
    path: string,
    model: GLTFObjectData
}

GLTFObjectData  :: struct {
    root: GLTFNode,
    meshes: []GLTFMesh,
}

GLTFMaterial :: struct {
    name: string,
    base_color_factor: vec4,
    base_color_texture: GLTFTexture,
    metallic_factor: f32,
    roughness_factor: f32,
    metallic_roughness_texture: GLTFTexture,
    normal_map: GLTFTexture,
}

GLTFTexture :: rd.Texture

GLTFMesh :: struct {
    vbo: rd.VertexBuffer,
    ibo: rd.IndexBuffer,
    primitives: []GLTFPrimitive
}

GLTFPrimitive :: struct {
    start,
    end: u32,
    material: GLTFMaterial
}

MeshData :: struct {
    name:       string,
    positions:  []vec3,
    normals:    []vec3,
    uvs:        []vec2,
    tangents:   []vec3,
    indices:    []u16,
    primitives: []GLTFPrimitive,
}

GLTFVertex :: struct {
    position: vec3,
    normal: vec3,
    uv: vec2,
    tangent: vec3
}

GLTFNode :: struct {
    mesh:       ^GLTFMesh,
    children:   []GLTFNode,
    aabb:       AABB,
    transform: Transform,
    bbox_vbo: rd.VertexBuffer,
}

load_asset :: proc(path: string) -> Asset {
    asset: Asset
    asset.name = fp.stem(path)
    asset.path = path
    asset.model = load_gltf(strings.clone_to_cstring(path, context.temp_allocator))
    
    return asset
}

load_gltf :: proc(path: cstring) -> GLTFObjectData {
    gltf_data := parse_file(path); defer gl.free(gltf_data)
    assert(len(gltf_data.buffers) == 1)
    assert(len(gltf_data.scene.nodes) == 1)
    root: GLTFNode
    meshes: [dynamic]GLTFMesh

    build_scene(gltf_data.scene.nodes[0], &root, &meshes, TRANSFORM_IDENTITY)
    return GLTFObjectData {
        root,
        meshes[:]
    }
}

build_scene :: proc(
    gl_node: ^gl.node,
    node: ^GLTFNode, 
    meshes: ^[dynamic]GLTFMesh,
    parent_transform: Transform
) {
    assert(!gl_node.has_matrix)
    transform := TRANSFORM_IDENTITY
    if gl_node.has_translation do transform.translation = gl_node.translation
    if gl_node.has_rotation {
        r := gl_node.rotation
        transform.rotation = quaternion(real = r.w, imag = r.x, jmag = r.y, kmag = r.z)
    }

    if gl_node.has_scale do transform.scale = gl_node.scale
    node.transform = transform

    parent_transform := Transform {
        translation = parent_transform.translation + transform.translation,
        scale = parent_transform.scale * transform.scale,
        rotation = parent_transform.rotation * transform.rotation
    }

    // Mesh
    mesh_data := load_mesh_data(gl_node.mesh)
    if len(mesh_data.primitives) != 0 {
        mesh := load_mesh(mesh_data)
        append(meshes, mesh)
        node.mesh = &meshes[len(meshes)-1]
        bbox: AABB = {min = max(f32), max = min(f32)}
        for &v in mesh_data.positions {
            v += parent_transform.translation
            q := parent_transform.rotation
            p := quaternion(w = 0, x = v.x, y = v.y, z = v.z)
            q_ := conj(q)
            p_ := q*p*q_
            v = {p_.x, p_.y, p_.z}
            if (v.x < bbox.min.x) do bbox.min.x = v.x;
            if (v.y < bbox.min.y) do bbox.min.y = v.y;
            if (v.z < bbox.min.z) do bbox.min.z = v.z;
            if (v.x > bbox.max.x) do bbox.max.x = v.x;
            if (v.y > bbox.max.y) do bbox.max.y = v.y;
            if (v.z > bbox.max.z) do bbox.max.z = v.z;
        }


        bbox_vertices := get_bbox_vertices(bbox)

        node.bbox_vbo = rd.create_vertex_buffer(bbox_vertices[:])

        delete(mesh_data.positions)
        delete(mesh_data.normals)
        delete(mesh_data.uvs)
        delete(mesh_data.tangents)
        node.aabb = bbox
    }

    if len(gl_node.children) == 0 do return
    children := make([]GLTFNode, len(gl_node.children))
    node.children = children
    for gl_child, i in gl_node.children {
        build_scene(gl_child, &node.children[i], meshes, transform)
    }
}


load_mesh :: proc(data: MeshData) -> GLTFMesh {
    mesh: GLTFMesh
    vert_count: uint = len(data.positions)
    index_count: uint = len(data.indices)
    len_bytes := vert_count*size_of(GLTFVertex) + index_count*size_of(u16)

    vertices := make([]GLTFVertex, len(data.positions))
    for i in 0..<len(data.positions) {
        vertices[i] = GLTFVertex {
            data.positions[i],
            data.normals[i],
            data.uvs[i],
            data.tangents[i]
        }
    }
    vbo := rd.create_vertex_buffer(vertices)
    ibo := rd.create_index_buffer(data.indices)

    mesh.vbo = vbo
    mesh.ibo = ibo
    mesh.primitives = data.primitives
    return mesh
}

load_material :: proc(m: ^gl.material) -> GLTFMaterial {
    assert(bool(m.has_pbr_metallic_roughness))
    material: GLTFMaterial;
    material.name = strings.clone_from_cstring(m.name)
    material.base_color_factor = m.pbr_metallic_roughness.base_color_factor
    material.metallic_factor = m.pbr_metallic_roughness.metallic_factor
    material.roughness_factor = m.pbr_metallic_roughness.roughness_factor
    base_color_tex := m.pbr_metallic_roughness.base_color_texture.texture
    material.base_color_texture = load_texture(base_color_tex)
    metallic_roughness_tex := m.pbr_metallic_roughness.metallic_roughness_texture.texture
    material.metallic_roughness_texture = load_texture(metallic_roughness_tex)
    material.normal_map = load_texture(m.normal_texture.texture)

    return material
}

load_texture :: proc(t: ^gl.texture) -> GLTFTexture {
    if t == nil do return {}
    view := t.image_.buffer_view
    data_multiptr := cast([^]byte)view.buffer.data
    ptr := mem.ptr_offset(data_multiptr, view.offset)
    data: [^]byte = cast([^]byte)ptr
    size := i32(view.size)
    width, height: i32
    pixels_ptr := stbi.load_from_memory(data, size, &width, &height, nil, 4)
    defer stbi.image_free(pixels_ptr)

    pixel_count := int(width * height * 4)
    pixels := slice.from_ptr(pixels_ptr, pixel_count)
    texture := rd.load_texture(pixels, u32(width), u32(height))

    return GLTFTexture(texture)
}

load_texture_from_memory :: proc(path: string, allocator := context.temp_allocator) -> (texture: rd.Texture, ok: bool) {
    file_data, read_err := os.read_entire_file_from_path(path, allocator)
    if read_err != nil {
        return
    }

    width, height: i32
    pixels_ptr := stbi.load_from_memory(
        raw_data(file_data),
        i32(len(file_data)),
        &width,
        &height,
        nil,
        4,
    )
    if pixels_ptr == nil {
        return
    }


    ok = true
    return
}

@(private = "file")
load_mesh_data :: proc(mesh: ^gl.mesh) -> MeshData {
    if mesh == nil do return {}
    positions:  [dynamic]vec3
    normals:    [dynamic]vec3
    tangents:   [dynamic]vec3
    uvs:        [dynamic]vec2
    indices:    [dynamic]u16
    primitives: [dynamic]GLTFPrimitive
    num_indices: uint
    for primitive, i in mesh.primitives {
        position_count := len(positions)
        material := load_material(primitive.material)
        for attribute in primitive.attributes {
            accessor := attribute.data
            #partial switch attribute.type {
                case .normal:   load_buffer_from_accessor(accessor, &normals)
                case .position: load_buffer_from_accessor(accessor, &positions)
                case .texcoord: load_buffer_from_accessor(accessor, &uvs)
                case .tangent:  load_buffer_from_accessor(accessor, &tangents)
            }
        }
        primitive_indices: [dynamic]u16; defer delete(primitive_indices)
        start := len(indices)
        load_buffer_from_accessor(primitive.indices, &primitive_indices)
        for i in primitive_indices do append(&indices, i + u16(position_count))
        for i := 0; i < len(primitive_indices); i += 3 {
            temp := primitive_indices[i]
            primitive_indices[i] = primitive_indices[i+2]
            primitive_indices[i+2] = temp
            
        }
        end := len(indices)
        gltf_primitive := GLTFPrimitive {
            start = u32(start),
            end = u32(end),
            material = material
        }
        append(&primitives, gltf_primitive)
    }
    if uvs == nil do uvs = make([dynamic]vec2, len(positions))
    if tangents == nil do tangents = make([dynamic]vec3, len(positions))

    {
        positions := len(positions)
        assert(positions == len(normals))
        assert(positions == len(uvs))
        assert(positions == len(tangents))
    }

    // for &p in positions do p.y *= -1
    // for &n in normals do n.y *= -1
    // for &t in tangents do t.y *= -1
    data: MeshData
    data.positions = positions[:]
    data.normals = normals[:]
    data.uvs = uvs[:]
    data.tangents = tangents[:]
    data.indices = indices[:]
    data.primitives = primitives[:]
    return data
}

get_bbox_vertices :: proc(bbox: AABB) -> [24]vec3 {
    return {
        vec3{bbox.min.x, bbox.min.y, bbox.min.z},
        vec3{bbox.max.x, bbox.min.y, bbox.min.z},
        vec3{bbox.max.x, bbox.max.y, bbox.min.z},
        vec3{bbox.min.x, bbox.max.y, bbox.min.z},
        vec3{bbox.min.x, bbox.min.y, bbox.min.z},
        vec3{bbox.min.x, bbox.min.y, bbox.max.z},
        vec3{bbox.max.x, bbox.min.y, bbox.max.z},
        vec3{bbox.min.x, bbox.min.y, bbox.max.z},
        vec3{bbox.max.x, bbox.max.y, bbox.max.z},
        vec3{bbox.min.x, bbox.max.y, bbox.max.z},
        vec3{bbox.max.x, bbox.min.y, bbox.max.z},
        vec3{bbox.max.x, bbox.min.y, bbox.min.z},
        vec3{bbox.max.x, bbox.max.y, bbox.min.z},
        vec3{bbox.max.x, bbox.max.y, bbox.max.z},
        vec3{bbox.min.x, bbox.max.y, bbox.min.z},
        vec3{bbox.min.x, bbox.max.y, bbox.max.z},
        vec3{bbox.min.x, bbox.min.y, bbox.min.z},
        vec3{bbox.min.x, bbox.max.y, bbox.min.z},
        vec3{bbox.max.x, bbox.min.y, bbox.min.z},
        vec3{bbox.max.x, bbox.max.y, bbox.min.z},
        vec3{bbox.min.x, bbox.min.y, bbox.max.z},
        vec3{bbox.min.x, bbox.max.y, bbox.max.z},
        vec3{bbox.max.x, bbox.min.y, bbox.max.z},
        vec3{bbox.max.x, bbox.max.y, bbox.max.z},
    }
}

@(private = "file")
load_buffer_from_accessor :: proc(accessor: ^gl.accessor, buffer: ^[dynamic]$T) {
    buffer_data := gl.buffer_view_data(accessor.buffer_view)
    data := cast([^]T)buffer_data
    for i in 0..<accessor.count do append(buffer, data[i])
}

@(private = "file")
parse_file :: proc(path: cstring) -> ^gl.data {
    data, err := gl.parse_file({}, path)
    if err != nil do log.errorf("error parsing file: {}", err)
    result := gl.load_buffers({}, data, path); assert(result == .success)
    result =  gl.validate(data); assert(result == .success)
    return data
}