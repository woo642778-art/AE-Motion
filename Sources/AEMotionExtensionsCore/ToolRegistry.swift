import Foundation

public enum ToolRegistry {
    public static let all: [ToolDescriptor] = [
        .init(id: "easing.curve", title: "Easing Curve Generator", subtitle: "Generate motion curves and sampled keyframes", section: .extensions),
        .init(id: "bpm.frames", title: "BPM / Beat / Frame Calculator", subtitle: "Convert beats, seconds, and frames", section: .utilities),
        .init(id: "random.values", title: "Random Value Generator", subtitle: "Seeded repeatable random values", section: .scripts),
        .init(id: "color.palette", title: "Color Palette Generator", subtitle: "Build harmonic color palettes", section: .utilities),
        .init(id: "expression.helper", title: "Expression Helper", subtitle: "Safe reusable motion formulas", section: .scripts),
        .init(id: "layer.offset", title: "Layer Offset Planner", subtitle: "Plan sequential timing offsets", section: .utilities),
        .init(id: "text.animator", title: "Text Animator Presets", subtitle: "Preview structured text animation recipes", section: .presets),
        .init(id: "camera.shake", title: "Camera Shake Generator", subtitle: "Generate deterministic shake samples", section: .extensions),
        .init(id: "motion.presets", title: "Motion Preset Browser", subtitle: "Browse curated motion recipes", section: .presets),
    ]
}
