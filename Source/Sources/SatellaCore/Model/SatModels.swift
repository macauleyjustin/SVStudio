import Foundation

public struct SatCanvas: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct SatExpressionRef: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var file: String

    public init(id: String, name: String, file: String) {
        self.id = id
        self.name = name
        self.file = file
    }
}

public struct SatAnimationRef: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var file: String
    public var autoPlay: Bool?

    public init(id: String, name: String, file: String, autoPlay: Bool? = nil) {
        self.id = id
        self.name = name
        self.file = file
        self.autoPlay = autoPlay
    }
}

public struct SatEffectRef: Codable, Sendable, Equatable {
    public var id: String
    public var file: String

    public init(id: String, file: String) {
        self.id = id
        self.file = file
    }
}

public struct SatFeatures: Codable, Sendable, Equatable {
    public var faceTracking: Bool?
    public var handTracking: Bool?
    public var lipSync: Bool?
    public var physics: Bool?
    public var breastPhysics: Bool?
    public var effects: Bool?
    public var concealedEyes: Bool?

    public init(
        faceTracking: Bool? = true,
        handTracking: Bool? = true,
        lipSync: Bool? = true,
        physics: Bool? = true,
        breastPhysics: Bool? = false,
        effects: Bool? = false,
        concealedEyes: Bool? = false
    ) {
        self.faceTracking = faceTracking
        self.handTracking = handTracking
        self.lipSync = lipSync
        self.physics = physics
        self.breastPhysics = breastPhysics
        self.effects = effects
        self.concealedEyes = concealedEyes
    }
}

public struct SatManifest: Codable, Sendable, Equatable {
    public var format: String
    public var schemaVersion: String
    public var id: String
    public var name: String
    public var version: String?
    public var author: String?
    public var description: String?
    public var canvas: SatCanvas
    public var model: String
    public var rig: String
    public var physics: String?
    public var defaultExpression: String?
    public var expressions: [SatExpressionRef]?
    public var animations: [SatAnimationRef]?
    public var effects: [SatEffectRef]?
    public var features: SatFeatures?

    public init(
        format: String = "satella.avatar",
        schemaVersion: String = "1.0.0",
        id: String,
        name: String,
        version: String? = "1.0.0",
        author: String? = nil,
        description: String? = nil,
        canvas: SatCanvas,
        model: String = "model.json",
        rig: String = "rig.json",
        physics: String? = nil,
        defaultExpression: String? = nil,
        expressions: [SatExpressionRef]? = nil,
        animations: [SatAnimationRef]? = nil,
        effects: [SatEffectRef]? = nil,
        features: SatFeatures? = nil
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.canvas = canvas
        self.model = model
        self.rig = rig
        self.physics = physics
        self.defaultExpression = defaultExpression
        self.expressions = expressions
        self.animations = animations
        self.effects = effects
        self.features = features
    }
}

public enum SatAlphaMode: String, Codable, Sendable {
    case straight
    case premultiplied
}

public struct SatTextureSpec: Codable, Sendable, Equatable {
    public var id: String
    public var file: String
    public var width: Int
    public var height: Int
    public var alphaMode: SatAlphaMode?

    public init(id: String, file: String, width: Int, height: Int, alphaMode: SatAlphaMode? = .straight) {
        self.id = id
        self.file = file
        self.width = width
        self.height = height
        self.alphaMode = alphaMode
    }
}

public struct SatPartSpec: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var parent: String?
    public var visible: Bool?
    public var opacity: Double?

    public init(id: String, name: String, parent: String? = nil, visible: Bool? = true, opacity: Double? = 1.0) {
        self.id = id
        self.name = name
        self.parent = parent
        self.visible = visible
        self.opacity = opacity
    }
}

public enum SatBlendMode: String, Codable, Sendable {
    case normal
    case additive
    case multiply
    case screen
}

public struct SatDrawableSpec: Codable, Sendable, Equatable {
    public var id: String
    public var part: String?
    public var mesh: String
    public var drawOrder: Double
    public var visible: Bool?
    public var opacity: Double?
    public var blendMode: SatBlendMode?
    public var doubleSided: Bool?

    public init(
        id: String,
        part: String? = nil,
        mesh: String,
        drawOrder: Double,
        visible: Bool? = true,
        opacity: Double? = 1.0,
        blendMode: SatBlendMode? = .normal,
        doubleSided: Bool? = true
    ) {
        self.id = id
        self.part = part
        self.mesh = mesh
        self.drawOrder = drawOrder
        self.visible = visible
        self.opacity = opacity
        self.blendMode = blendMode
        self.doubleSided = doubleSided
    }
}

public struct SatModelLayout: Codable, Sendable, Equatable {
    public var textures: [SatTextureSpec]
    public var parts: [SatPartSpec]?
    public var drawables: [SatDrawableSpec]

    public init(textures: [SatTextureSpec], parts: [SatPartSpec]? = nil, drawables: [SatDrawableSpec]) {
        self.textures = textures
        self.parts = parts
        self.drawables = drawables
    }
}

public struct SatMesh: Codable, Sendable, Equatable {
    public var id: String
    public var texture: String
    public var parent: String?
    public var part: String?
    public var drawOrder: Double?
    public var opacity: Double?
    public var blendMode: SatBlendMode?
    public var clipMasks: [String]?
    public var invertedMask: Bool?
    public var uvClipRect: [Double]?
    public var vertices: [[Double]]
    public var uv: [[Double]]
    public var triangles: [Int]

    public init(
        id: String,
        texture: String,
        parent: String? = nil,
        part: String? = nil,
        drawOrder: Double? = nil,
        opacity: Double? = nil,
        blendMode: SatBlendMode? = nil,
        clipMasks: [String]? = nil,
        invertedMask: Bool? = nil,
        uvClipRect: [Double]? = nil,
        vertices: [[Double]],
        uv: [[Double]],
        triangles: [Int]
    ) {
        self.id = id
        self.texture = texture
        self.parent = parent
        self.part = part
        self.drawOrder = drawOrder
        self.opacity = opacity
        self.blendMode = blendMode
        self.clipMasks = clipMasks
        self.invertedMask = invertedMask
        self.uvClipRect = uvClipRect
        self.vertices = vertices
        self.uv = uv
        self.triangles = triangles
    }
}

public struct SatParameterSpec: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var group: String?
    public var min: Double
    public var `default`: Double
    public var max: Double
    public var `repeat`: Bool?

    public init(id: String, name: String? = nil, group: String? = nil, min: Double, default: Double, max: Double, repeat: Bool? = false) {
        self.id = id
        self.name = name
        self.group = group
        self.min = min
        self.`default` = `default`
        self.max = max
        self.`repeat` = `repeat`
    }
}

public struct SatAxisSpec: Codable, Sendable, Equatable {
    public var parameter: String
    public var keys: [Double]

    public init(parameter: String, keys: [Double]) {
        self.parameter = parameter
        self.keys = keys
    }
}

public enum SatDeformerType: String, Codable, Sendable {
    case rotation
    case warp
}

public struct SatBounds: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct SatDeformerKeyform: Codable, Sendable, Equatable {
    public var angleDeg: Double?
    public var translate: [Double]?
    public var scale: [Double]?
    public var opacity: Double?
    public var gridOffsets: [[Double]]?

    public init(
        angleDeg: Double? = nil,
        translate: [Double]? = nil,
        scale: [Double]? = nil,
        opacity: Double? = nil,
        gridOffsets: [[Double]]? = nil
    ) {
        self.angleDeg = angleDeg
        self.translate = translate
        self.scale = scale
        self.opacity = opacity
        self.gridOffsets = gridOffsets
    }
}

public struct SatDeformerSpec: Codable, Sendable, Equatable {
    public var id: String
    public var parent: String?
    public var type: SatDeformerType
    public var pivot: [Double]?
    public var bounds: SatBounds?
    public var rows: Int?
    public var cols: Int?
    public var axes: [SatAxisSpec]?
    public var keyforms: [SatDeformerKeyform]?

    public init(
        id: String,
        parent: String? = nil,
        type: SatDeformerType,
        pivot: [Double]? = nil,
        bounds: SatBounds? = nil,
        rows: Int? = nil,
        cols: Int? = nil,
        axes: [SatAxisSpec]? = nil,
        keyforms: [SatDeformerKeyform]? = nil
    ) {
        self.id = id
        self.parent = parent
        self.type = type
        self.pivot = pivot
        self.bounds = bounds
        self.rows = rows
        self.cols = cols
        self.axes = axes
        self.keyforms = keyforms
    }
}

public struct SatMeshKeyform: Codable, Sendable, Equatable {
    public var opacity: Double?
    public var drawOrderOffset: Double?
    public var translate: [Double]?
    public var scale: [Double]?
    public var pivot: [Double]?
    public var vertexDeltas: [[Double]]?

    public init(
        opacity: Double? = nil,
        drawOrderOffset: Double? = nil,
        translate: [Double]? = nil,
        scale: [Double]? = nil,
        pivot: [Double]? = nil,
        vertexDeltas: [[Double]]? = nil
    ) {
        self.opacity = opacity
        self.drawOrderOffset = drawOrderOffset
        self.translate = translate
        self.scale = scale
        self.pivot = pivot
        self.vertexDeltas = vertexDeltas
    }
}

public struct SatMeshBindingSpec: Codable, Sendable, Equatable {
    public var meshId: String
    public var axes: [SatAxisSpec]
    public var keyforms: [SatMeshKeyform]

    public init(meshId: String, axes: [SatAxisSpec], keyforms: [SatMeshKeyform]) {
        self.meshId = meshId
        self.axes = axes
        self.keyforms = keyforms
    }
}

public enum SatDragTrigger: String, Codable, Sendable, Equatable {
    case move
    case shake
    case dragUp
    case dragDown
    case dragHorizontal
}

public struct SatDragReactionSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var parameter: String
    public var trigger: SatDragTrigger
    public var targetValue: Double
    public var restValue: Double?
    public var sensitivity: Double?
    public var holdWhileDragging: Bool?
    public var attackSeconds: Double?
    public var releaseSeconds: Double?

    public init(
        id: String,
        name: String,
        parameter: String,
        trigger: SatDragTrigger = .move,
        targetValue: Double,
        restValue: Double? = nil,
        sensitivity: Double? = nil,
        holdWhileDragging: Bool? = true,
        attackSeconds: Double? = 0.08,
        releaseSeconds: Double? = 0.18
    ) {
        self.id = id
        self.name = name
        self.parameter = parameter
        self.trigger = trigger
        self.targetValue = targetValue
        self.restValue = restValue
        self.sensitivity = sensitivity
        self.holdWhileDragging = holdWhileDragging
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }
}

public struct SatRig: Codable, Sendable, Equatable {
    public var parameters: [SatParameterSpec]
    public var deformers: [SatDeformerSpec]
    public var meshBindings: [SatMeshBindingSpec]?
    public var dragReactions: [SatDragReactionSpec]?

    public init(
        parameters: [SatParameterSpec],
        deformers: [SatDeformerSpec],
        meshBindings: [SatMeshBindingSpec]? = nil,
        dragReactions: [SatDragReactionSpec]? = nil
    ) {
        self.parameters = parameters
        self.deformers = deformers
        self.meshBindings = meshBindings
        self.dragReactions = dragReactions
    }
}

public enum SatPhysicsCategory: String, Codable, Sendable {
    case hair
    case clothing
    case breast
    case accessory
    case custom
}

public enum SatPhysicsPreset: String, Codable, Sendable {
    case light_hair
    case heavy_fabric
    case soft_body
    case accessory
    case custom
}

public enum SatPhysicsType: String, Codable, Sendable {
    case pendulum
    case spring2d
}

public enum SatPhysicsIOKind: String, Codable, Sendable {
    case x
    case y
    case angle
}

public struct SatPhysicsNodeSpec: Codable, Sendable, Equatable {
    public var length: Double
    public var mass: Double
    public var stiffness: Double
    public var damping: Double

    public init(length: Double, mass: Double, stiffness: Double, damping: Double) {
        self.length = length
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
    }
}

public struct SatPhysicsInputSpec: Codable, Sendable, Equatable {
    public var parameter: String
    public var weight: Double
    public var velocityWeight: Double?
    public var kind: SatPhysicsIOKind
    public var reflect: Bool?

    public init(parameter: String, weight: Double, velocityWeight: Double? = nil, kind: SatPhysicsIOKind, reflect: Bool? = false) {
        self.parameter = parameter
        self.weight = weight
        self.velocityWeight = velocityWeight
        self.kind = kind
        self.reflect = reflect
    }
}

public struct SatPhysicsOutputSpec: Codable, Sendable, Equatable {
    public var parameter: String
    public var nodeIndex: Int?
    public var scale: Double
    public var weight: Double?
    public var kind: SatPhysicsIOKind
    public var reflect: Bool?

    public init(parameter: String, nodeIndex: Int? = nil, scale: Double, weight: Double? = 1.0, kind: SatPhysicsIOKind, reflect: Bool? = false) {
        self.parameter = parameter
        self.nodeIndex = nodeIndex
        self.scale = scale
        self.weight = weight
        self.kind = kind
        self.reflect = reflect
    }
}

public struct SatPhysicsGroupSpec: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var category: SatPhysicsCategory?
    public var preset: SatPhysicsPreset?
    public var type: SatPhysicsType
    public var stiffness: Double?
    public var damping: Double?
    public var inertia: Double?
    public var gravityScale: Double?
    public var windWeight: Double?
    public var maxOutput: Double?
    public var nodes: [SatPhysicsNodeSpec]?
    public var inputs: [SatPhysicsInputSpec]
    public var outputs: [SatPhysicsOutputSpec]

    public init(
        id: String,
        name: String,
        category: SatPhysicsCategory? = nil,
        preset: SatPhysicsPreset? = nil,
        type: SatPhysicsType,
        stiffness: Double? = nil,
        damping: Double? = nil,
        inertia: Double? = nil,
        gravityScale: Double? = nil,
        windWeight: Double? = nil,
        maxOutput: Double? = nil,
        nodes: [SatPhysicsNodeSpec]? = nil,
        inputs: [SatPhysicsInputSpec],
        outputs: [SatPhysicsOutputSpec]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.preset = preset
        self.type = type
        self.stiffness = stiffness
        self.damping = damping
        self.inertia = inertia
        self.gravityScale = gravityScale
        self.windWeight = windWeight
        self.maxOutput = maxOutput
        self.nodes = nodes
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct SatPhysicsSpec: Codable, Sendable, Equatable {
    public var fixedTimestep: Double
    public var gravity: [Double]?
    public var wind: [Double]?
    public var groups: [SatPhysicsGroupSpec]

    public init(fixedTimestep: Double = 1.0 / 60.0, gravity: [Double]? = [0, 1], wind: [Double]? = [0, 0], groups: [SatPhysicsGroupSpec]) {
        self.fixedTimestep = fixedTimestep
        self.gravity = gravity
        self.wind = wind
        self.groups = groups
    }
}

public enum SatExpressionBlend: String, Codable, Sendable {
    case overwrite
    case add
    case multiply
}

public struct SatExpressionParam: Codable, Sendable, Equatable {
    public var parameter: String
    public var value: Double
    public var blend: SatExpressionBlend

    public init(parameter: String, value: Double, blend: SatExpressionBlend) {
        self.parameter = parameter
        self.value = value
        self.blend = blend
    }
}

public struct SatExpression: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var fadeInSeconds: Double?
    public var fadeOutSeconds: Double?
    public var parameters: [SatExpressionParam]

    public init(id: String, name: String, fadeInSeconds: Double? = 0.25, fadeOutSeconds: Double? = 0.25, parameters: [SatExpressionParam]) {
        self.id = id
        self.name = name
        self.fadeInSeconds = fadeInSeconds
        self.fadeOutSeconds = fadeOutSeconds
        self.parameters = parameters
    }
}

public enum SatKeyframeInterp: String, Codable, Sendable {
    case linear
    case smooth
    case stepped
}

public struct SatKeyframe: Codable, Sendable, Equatable {
    public var time: Double
    public var value: Double

    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct SatAnimationTrack: Codable, Sendable, Equatable {
    public var parameter: String
    public var blend: SatExpressionBlend?
    public var interpolation: SatKeyframeInterp?
    public var keyframes: [SatKeyframe]

    public init(parameter: String, blend: SatExpressionBlend? = .add, interpolation: SatKeyframeInterp? = .smooth, keyframes: [SatKeyframe]) {
        self.parameter = parameter
        self.blend = blend
        self.interpolation = interpolation
        self.keyframes = keyframes
    }
}

public struct SatAnimation: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var duration: Double
    public var loop: Bool?
    public var fadeInSeconds: Double?
    public var fadeOutSeconds: Double?
    public var tracks: [SatAnimationTrack]

    public init(id: String, name: String, duration: Double, loop: Bool? = true, fadeInSeconds: Double? = 0.2, fadeOutSeconds: Double? = 0.2, tracks: [SatAnimationTrack]) {
        self.id = id
        self.name = name
        self.duration = duration
        self.loop = loop
        self.fadeInSeconds = fadeInSeconds
        self.fadeOutSeconds = fadeOutSeconds
        self.tracks = tracks
    }
}

public enum SatEffectKind: String, Codable, Sendable {
    case miasma
    case aura_wisp
    case particles
}

public enum SatEffectPlacement: String, Codable, Sendable {
    case behind_avatar
    case above_cloak
    case foreground
}

public enum SatEffectBlend: String, Codable, Sendable {
    case alpha
    case additive
    case screen
}

public struct SatEffectRegion: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var weight: Double?

    public init(x: Double, y: Double, width: Double, height: Double, weight: Double? = 1.0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.weight = weight
    }
}

public struct SatEffectLayer: Codable, Sendable, Equatable {
    public var id: String
    public var kind: SatEffectKind
    public var placement: SatEffectPlacement
    public var blendMode: SatEffectBlend?
    public var chromaSafe: Bool?
    public var texture: String?
    public var particleCount: Int
    public var opacity: Double?
    public var riseSpeed: Double?
    public var driftX: Double?
    public var turbulence: Double?
    public var swirlFrequency: Double?
    public var swirlAmplitude: Double?
    public var sizeRange: [Double]?
    public var lifeRange: [Double]?
    public var intensityParam: String?
    public var followDeformer: String?
    public var exclusionBoxes: [SatBounds]?
    public var colors: [[Double]]
    public var regions: [SatEffectRegion]

    public init(
        id: String,
        kind: SatEffectKind,
        placement: SatEffectPlacement,
        blendMode: SatEffectBlend? = .alpha,
        chromaSafe: Bool? = true,
        texture: String? = nil,
        particleCount: Int,
        opacity: Double? = 0.65,
        riseSpeed: Double? = 18.0,
        driftX: Double? = 0.0,
        turbulence: Double? = 10.0,
        swirlFrequency: Double? = 1.1,
        swirlAmplitude: Double? = 14.0,
        sizeRange: [Double]? = nil,
        lifeRange: [Double]? = nil,
        intensityParam: String? = nil,
        followDeformer: String? = nil,
        exclusionBoxes: [SatBounds]? = nil,
        colors: [[Double]],
        regions: [SatEffectRegion]
    ) {
        self.id = id
        self.kind = kind
        self.placement = placement
        self.blendMode = blendMode
        self.chromaSafe = chromaSafe
        self.texture = texture
        self.particleCount = particleCount
        self.opacity = opacity
        self.riseSpeed = riseSpeed
        self.driftX = driftX
        self.turbulence = turbulence
        self.swirlFrequency = swirlFrequency
        self.swirlAmplitude = swirlAmplitude
        self.sizeRange = sizeRange
        self.lifeRange = lifeRange
        self.intensityParam = intensityParam
        self.followDeformer = followDeformer
        self.exclusionBoxes = exclusionBoxes
        self.colors = colors
        self.regions = regions
    }
}

public struct SatEffectsSpec: Codable, Sendable, Equatable {
    public var id: String
    public var layers: [SatEffectLayer]

    public init(id: String, layers: [SatEffectLayer]) {
        self.id = id
        self.layers = layers
    }
}

public struct SatLoadedAvatar: Sendable {
    public var sourceURL: URL?
    public var manifest: SatManifest
    public var model: SatModelLayout
    public var rig: SatRig
    public var physics: SatPhysicsSpec?
    public var meshes: [String: SatMesh]
    public var textureData: [String: Data]
    public var expressions: [SatExpression]
    public var animations: [SatAnimation]
    public var effects: [SatEffectsSpec]

    public init(
        sourceURL: URL? = nil,
        manifest: SatManifest,
        model: SatModelLayout,
        rig: SatRig,
        physics: SatPhysicsSpec? = nil,
        meshes: [String: SatMesh],
        textureData: [String: Data],
        expressions: [SatExpression],
        animations: [SatAnimation],
        effects: [SatEffectsSpec]
    ) {
        self.sourceURL = sourceURL
        self.manifest = manifest
        self.model = model
        self.rig = rig
        self.physics = physics
        self.meshes = meshes
        self.textureData = textureData
        self.expressions = expressions
        self.animations = animations
        self.effects = effects
    }
}
