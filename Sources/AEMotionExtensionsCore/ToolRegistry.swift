import Foundation

public enum ToolRegistry {
    public static let all: [ToolDescriptor] = [
        .init(id: "speed.remap", title: "Speed Remap Studio", subtitle: "Velocity graph, reverse, freeze and video speed keyframes", section: .extensions),
        .init(id: "easing.curve", title: "Easing Curve Generator", subtitle: "Generate motion curves and sampled keyframes", section: .extensions),
        .init(id: "camera.shake", title: "Camera Shake Generator", subtitle: "Generate deterministic shake samples", section: .extensions),
        .init(id: "random.values", title: "Random Value Generator", subtitle: "Seeded repeatable random values", section: .scripts),
        .init(id: "expression.helper", title: "Expression Helper", subtitle: "Copy reusable motion formulas", section: .scripts),
        .init(id: "text.animator", title: "Text Animator Presets", subtitle: "Structured text animation recipes", section: .presets),
        .init(id: "motion.presets", title: "Motion Preset Browser", subtitle: "Browse curated motion recipes", section: .presets),
        .init(id: "bpm.frames", title: "BPM / Beat / Frame Calculator", subtitle: "Convert beats, seconds and frames", section: .utilities),
        .init(id: "color.palette", title: "Color Palette Generator", subtitle: "Build harmonic color palettes", section: .utilities),
        .init(id: "layer.offset", title: "Layer Offset Planner", subtitle: "Plan sequential timing offsets", section: .utilities),
        .init(id: "host.diagnostics", title: "Native Host Diagnostics", subtitle: "Inspect the speed/timeline bridge for direct apply", section: .utilities),
    ]
}
